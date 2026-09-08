import Foundation
import Observation

/// What the screens talk to. It owns the choice of backend, sequences the two
/// halves of a payment, and holds the last thing the backend said.
///
/// The sequencing is the part worth reading. A deposit is never one step: the
/// app asks the backend to open an intent, takes the player through the payment
/// provider, and then asks the backend to settle that intent. The balance is
/// whatever comes back from the third step. Nothing in between is treated as
/// money, and if the app is killed after the payment but before the settlement,
/// the intent is still sitting on the server waiting to be resolved.
@MainActor
@Observable
final class VaultStore {
    static let shared = VaultStore()

    private(set) var summary: VaultSummary = .empty
    private(set) var transactions: [VaultTransaction] = []
    private(set) var withdrawals: [WithdrawalRequest] = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var hasLoadedOnce = false

    private var loadTask: Task<Void, Never>?

    private init() {}

    /// The real backend whenever there is one to talk to. The in-app sandbox is
    /// only reached when there is no project configured or nobody is signed in,
    /// so a signed-in player's money is always the server's business.
    var backend: VaultBackend {
        let supabase = SupabaseVaultBackend()
        return supabase.isAvailable ? supabase : SandboxVaultBackend.shared
    }

    /// True while the money is test money, which is everywhere today. Drives the
    /// Demo Funds labelling.
    var isSandbox: Bool {
        summary.isSandbox || VaultProviders.isSandbox
    }

    var isCloudBacked: Bool {
        SupabaseVaultBackend().isAvailable
    }

    var currencyCode: String { summary.currencyCode }

    var pendingWithdrawalRequests: [WithdrawalRequest] {
        withdrawals.filter { $0.status.isOpen }
    }

    // MARK: - Loading

    func refresh() {
        loadTask?.cancel()
        loadTask = Task { await load() }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            let backend = self.backend
            summary = try await backend.openVault()
            transactions = try await backend.transactions(limit: 100)
            withdrawals = try await backend.withdrawals()
            lastError = nil
        } catch {
            lastError = VaultError.from(error).errorDescription
        }
    }

    private func reloadQuietly() async {
        let backend = self.backend
        summary = (try? await backend.summary()) ?? summary
        transactions = (try? await backend.transactions(limit: 100)) ?? transactions
        withdrawals = (try? await backend.withdrawals()) ?? withdrawals
    }

    /// Called when the account changes hands so no balance follows the previous
    /// player. Cloud money stays on the server where it belongs.
    func clearLocalState() {
        SandboxVaultBackend.shared.reset()
        summary = .empty
        transactions = []
        withdrawals = []
        hasLoadedOnce = false
    }

    // MARK: - Adding money

    /// Opens a deposit, takes the player through the provider, and asks the
    /// backend to settle it. The amount added is the backend's answer, not the
    /// amount passed in here.
    @discardableResult
    func addMoney(_ amount: Money) async throws -> DepositIntent {
        let backend = self.backend
        let key = VaultIdempotency.key("deposit", String(amount.cents))
        let currency = VaultFX.normalize(summary.currencyCode)

        let intent = try await backend.createDepositIntent(
            amount: amount,
            purpose: .vaultDeposit,
            tableInviteCode: nil,
            currencyCode: currency,
            idempotencyKey: key
        )
        await reloadQuietly()

        do {
            _ = try await VaultProviders.payment.authorize(
                amount: amount,
                currencyCode: currency,
                reference: intent.referenceCode,
                summaryLabel: "Pot Master Vault"
            )
        } catch {
            // The player backed out or the provider declined. Canceling is an
            // honest action of its own — it never credits the Vault.
            _ = try? await backend.cancelDeposit(intentID: intent.id)
            await reloadQuietly()
            throw VaultError.from(error)
        }

        let settled = try await backend.confirmDeposit(intentID: intent.id)
        await reloadQuietly()

        guard settled.status.isVerified else {
            throw VaultError.paymentFailed(settled.failureReason ?? "The payment did not go through.")
        }
        return settled
    }

    // MARK: - Table buy-ins

    /// Tells the backend what a table's buy-in range is, so it can refuse
    /// anything outside it. The host does this when the table is made.
    @discardableResult
    func registerTable(
        inviteCode: String,
        minimum: Money,
        maximum: Money,
        currencyCode: String
    ) async -> TableBuyInLimits? {
        try? await backend.registerTable(
            inviteCode: inviteCode,
            minimum: minimum,
            maximum: maximum,
            currencyCode: currencyCode
        )
    }

    func limits(forTable inviteCode: String) async -> TableBuyInLimits? {
        try? await backend.tableLimits(inviteCode: inviteCode)
    }

    /// Moves money from the Vault onto a table.
    @discardableResult
    func buyInFromVault(
        inviteCode: String,
        amount: Money,
        playerKey: String,
        displayName: String
    ) async throws -> TableBuyInReceipt {
        let receipt = try await backend.buyIn(
            inviteCode: inviteCode,
            amount: amount,
            source: .vault,
            playerKey: playerKey,
            displayName: displayName,
            paymentIntentID: nil,
            idempotencyKey: VaultIdempotency.key("buyin", inviteCode, String(amount.cents))
        )
        await reloadQuietly()
        return receipt
    }

    /// Pays for a seat straight through the provider. The verified payment lands
    /// on the table without passing through the available balance, and the
    /// buy-in is only accepted once the backend has settled that payment.
    @discardableResult
    func buyInWithApplePay(
        inviteCode: String,
        amount: Money,
        playerKey: String,
        displayName: String
    ) async throws -> TableBuyInReceipt {
        let backend = self.backend
        let tableCurrency = (try? await backend.tableLimits(inviteCode: inviteCode))?.currencyCode
            ?? summary.currencyCode
        let walletCurrency = VaultFX.normalize(summary.currencyCode)
        guard let charged = VaultFX.convert(amount, from: tableCurrency, to: walletCurrency) else {
            throw VaultError.backend("No exchange rate for that buy-in.")
        }

        let intent = try await backend.createDepositIntent(
            amount: charged,
            purpose: .tableBuyIn,
            tableInviteCode: inviteCode,
            currencyCode: walletCurrency,
            idempotencyKey: VaultIdempotency.key("tablepay", inviteCode, String(amount.cents))
        )

        do {
            _ = try await VaultProviders.payment.authorize(
                amount: charged,
                currencyCode: walletCurrency,
                reference: intent.referenceCode,
                summaryLabel: "Buy-in at table \(inviteCode)"
            )
        } catch {
            _ = try? await backend.cancelDeposit(intentID: intent.id)
            await reloadQuietly()
            throw VaultError.from(error)
        }

        let settled = try await backend.confirmDeposit(intentID: intent.id)
        guard settled.status.isVerified else {
            await reloadQuietly()
            throw VaultError.paymentFailed(settled.failureReason ?? "The payment did not go through.")
        }

        let receipt = try await backend.buyIn(
            inviteCode: inviteCode,
            amount: amount,
            source: .applePay,
            playerKey: playerKey,
            displayName: displayName,
            paymentIntentID: settled.id,
            idempotencyKey: VaultIdempotency.stableKey("buyin_intent", settled.id.uuidString)
        )
        await reloadQuietly()
        return receipt
    }

    /// Rejected on every backend. Settlement is posted by the poker engine.
    func recordHand(inviteCode: String, handID: String, deltas: [String: Money]) async {
        _ = inviteCode
        _ = handID
        _ = deltas
    }

    func startHand(inviteCode: String) async throws -> SharedTableHand {
        try await backend.startHand(inviteCode: inviteCode)
    }

    func act(
        inviteCode: String,
        action: HandMove,
        amount: Money?,
        actionID: String = VaultIdempotency.key("act")
    ) async throws -> SharedTableHand {
        try await backend.act(
            inviteCode: inviteCode,
            action: action,
            amount: amount,
            actionID: actionID
        )
    }

    func handView(inviteCode: String) async throws -> SharedTableHand? {
        try await backend.handView(inviteCode: inviteCode)
    }

    /// Stands the player up. What comes back is what the backend calculated, and
    /// it is already in the Vault by the time this returns.
    func leaveTable(inviteCode: String) async throws -> TableSettlement {
        let settlement = try await backend.leaveTable(
            inviteCode: inviteCode,
            idempotencyKey: VaultIdempotency.stableKey("leave", inviteCode)
        )
        await reloadQuietly()
        return settlement
    }

    // MARK: - Cashing out

    func feeForWithdrawal(_ amount: Money) -> Money {
        Money(
            cents: summary.withdrawalFeeFlat.cents
                + (amount.cents * summary.withdrawalFeeBasisPoints) / 10_000
        )
    }

    func netForWithdrawal(_ amount: Money) -> Money {
        (amount - feeForWithdrawal(amount)).clampedToNonNegative()
    }

    @discardableResult
    func requestCashOut(_ amount: Money, currencyCode: String? = nil) async throws -> WithdrawalRequest {
        let payout = CurrencyPreferences.normalizedCurrencyCode(currencyCode ?? summary.currencyCode)
        let request = try await backend.requestWithdrawal(
            amount: amount,
            currencyCode: payout,
            idempotencyKey: VaultIdempotency.key("cashout", payout, String(amount.cents))
        )
        await reloadQuietly()
        return request
    }

    @discardableResult
    func cancelCashOut(_ id: UUID) async throws -> WithdrawalRequest {
        let request = try await backend.cancelWithdrawal(id: id)
        await reloadQuietly()
        return request
    }

    /// Demo only. Walks a pending cash-out to its finished state so the whole
    /// range of withdrawal states can be seen without a payout rail.
    @discardableResult
    func settleCashOutInSandbox(_ id: UUID, succeeds: Bool = true) async throws -> WithdrawalRequest {
        let request = try await backend.settleWithdrawalInSandbox(id: id, succeeds: succeeds)
        await reloadQuietly()
        return request
    }
}
