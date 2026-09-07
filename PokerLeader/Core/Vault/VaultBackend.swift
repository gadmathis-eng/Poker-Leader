import Foundation

/// The only way the app is allowed to touch money.
///
/// Every method here is a request, not an instruction: the app asks, and the
/// backend decides what the balances become. There is deliberately no way to
/// set a balance, credit a win, or mark a payment verified from this side.
///
/// Two things follow from that and are worth stating outright, because they are
/// what keeps the client honest:
///
/// - Amounts the app sends are *intent*. Amounts the app reads back are *fact*.
///   A deposit is worth nothing until `confirmDeposit` has run through the
///   provider and the backend has settled it, and a buy-in paid with Apple Pay
///   has to name a deposit the backend already verified.
/// - Every mutating call carries an idempotency key. Send the same key twice —
///   after a timeout, a retry, a backgrounded app — and the second call returns
///   the first result instead of moving money again.
@MainActor
protocol VaultBackend {
    /// Whether this backend can serve the signed-in player at all.
    var isAvailable: Bool { get }

    /// Creates the player's accounts if this is their first visit, and returns
    /// where they stand.
    func openVault() async throws -> VaultSummary
    func summary() async throws -> VaultSummary
    func transactions(limit: Int) async throws -> [VaultTransaction]

    /// Starts a deposit. Returns something to pay, not money in the Vault.
    func createDepositIntent(
        amount: Money,
        purpose: DepositPurpose,
        tableInviteCode: String?,
        idempotencyKey: String
    ) async throws -> DepositIntent

    /// Settles a deposit the payment provider has authorised. In production the
    /// provider's signed webhook does this server-side and the app only polls;
    /// while the sandbox is on, this stands in for that webhook.
    func confirmDeposit(intentID: UUID, succeeds: Bool) async throws -> DepositIntent

    func registerTable(
        inviteCode: String,
        minimum: Money,
        maximum: Money,
        currencyCode: String
    ) async throws -> TableBuyInLimits

    func tableLimits(inviteCode: String) async throws -> TableBuyInLimits?

    func buyIn(
        inviteCode: String,
        amount: Money,
        source: TableBuyInSource,
        playerKey: String,
        displayName: String,
        paymentIntentID: UUID?,
        idempotencyKey: String
    ) async throws -> TableBuyInReceipt

    /// Chips in play for every seat. The only financial figure that crosses
    /// between players.
    func tableChips(inviteCode: String) async throws -> [TableChipCount]

    /// Posts the result of one hand. Zero-sum across the seats, host only, and
    /// keyed on the hand id so the same hand cannot be banked twice.
    func recordHand(
        inviteCode: String,
        handID: String,
        deltas: [String: Money]
    ) async throws

    /// Stands the player up and moves whatever the backend says their seat holds
    /// into their Vault.
    func leaveTable(inviteCode: String, idempotencyKey: String) async throws -> TableSettlement

    func requestWithdrawal(amount: Money, idempotencyKey: String) async throws -> WithdrawalRequest
    func withdrawals() async throws -> [WithdrawalRequest]
    func cancelWithdrawal(id: UUID) async throws -> WithdrawalRequest

    /// Demo only: walks a pending cash-out to a finished state so the states can
    /// be seen without a payout rail.
    func settleWithdrawalInSandbox(id: UUID, succeeds: Bool) async throws -> WithdrawalRequest
}

enum VaultIdempotency {
    /// A key that is stable for one user action and different for the next.
    /// Reusing it is the point: a retry after a dropped connection must land on
    /// the same key so the backend recognises the request it already handled.
    static func key(_ scope: String, _ parts: String...) -> String {
        ([scope] + parts + [UUID().uuidString]).joined(separator: ":")
    }

    /// A key derived only from what it identifies, for retrying one specific
    /// attempt rather than starting a new one.
    static func stableKey(_ scope: String, _ parts: String...) -> String {
        ([scope] + parts).joined(separator: ":")
    }
}
