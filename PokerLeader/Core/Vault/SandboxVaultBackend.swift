import Foundation

/// A stand-in server that runs inside the app, for demoing the Vault on a device
/// with no Supabase project attached.
///
/// It keeps the same shape as the real thing — the same accounts, the same
/// immutable double-entry postings, the same idempotency keys, the same refusal
/// to let a balance go negative — so the screens above it behave identically
/// whichever backend is underneath.
///
/// It is **not a security boundary**. Everything it holds lives on the device
/// and belongs to whoever is holding the phone. It exists so the flows can be
/// walked through with test money, and it steps aside the moment a real backend
/// is reachable: `VaultStore` picks `SupabaseVaultBackend` whenever the project
/// is configured and the player is signed in. It never runs against real money,
/// because the money it deals in does not exist.
@MainActor
final class SandboxVaultBackend: VaultBackend {
    static let shared = SandboxVaultBackend()

    var isAvailable: Bool { true }

    private var state: State
    private let storageKey = "vault.sandbox.state.v1"

    private init() {
        state = Self.load(key: "vault.sandbox.state.v1") ?? State()
    }

    // MARK: - Reading

    func openVault() async throws -> VaultSummary {
        try await summary()
    }

    func summary() async throws -> VaultSummary {
        let pendingDeposits = state.intents.values
            .filter { $0.purpose == .vaultDeposit && $0.status == .requiresConfirmation }
            .reduce(0) { $0 + $1.amountCents }

        var result = VaultSummary.empty
        result.available = Money(cents: state.balance(.available))
        result.inPlay = Money(cents: state.inPlayTotal)
        result.pendingDeposits = Money(cents: pendingDeposits)
        result.pendingWithdrawals = Money(cents: state.balance(.pendingWithdrawal))
        result.isSandbox = true
        return result
    }

    func transactions(limit: Int) async throws -> [VaultTransaction] {
        Array(state.statement.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
            .map(\.model)
    }

    // MARK: - Deposits

    func createDepositIntent(
        amount: Money,
        purpose: DepositPurpose,
        tableInviteCode: String?,
        idempotencyKey: String
    ) async throws -> DepositIntent {
        if let existing = state.intents.values.first(where: { $0.idempotencyKey == idempotencyKey }) {
            return existing.model
        }

        let summary = try await summary()
        guard amount >= summary.depositMinimum else {
            throw VaultError.amountOutOfRange(
                "The smallest deposit is \(summary.depositMinimum.formatted(currencyCode: "USD"))."
            )
        }
        guard amount <= summary.depositMaximum else {
            throw VaultError.amountOutOfRange(
                "The largest deposit is \(summary.depositMaximum.formatted(currencyCode: "USD"))."
            )
        }

        let intent = StoredIntent(
            id: UUID(),
            referenceCode: SandboxReference.code("PI"),
            amountCents: amount.cents,
            status: .requiresConfirmation,
            purpose: purpose,
            tableInviteCode: tableInviteCode?.uppercased(),
            idempotencyKey: idempotencyKey,
            consumed: false,
            failureReason: nil
        )
        state.intents[intent.id] = intent

        if purpose == .vaultDeposit {
            state.statement.append(
                StoredStatement(
                    kind: .deposit,
                    status: .pending,
                    amountCents: amount.cents,
                    intentID: intent.id,
                    detail: "Awaiting payment confirmation"
                )
            )
        }

        save()
        return intent.model
    }

    func confirmDeposit(intentID: UUID) async throws -> DepositIntent {
        guard var intent = state.intents[intentID] else {
            throw VaultError.backend("Unknown payment.")
        }

        // A replayed confirmation returns what already happened. The outcome is
        // this backend's, not the caller's — there is no way to ask for a fail.
        guard intent.status == .requiresConfirmation else { return intent.model }

        intent.status = .succeeded
        state.intents[intentID] = intent

        if intent.purpose == .vaultDeposit {
            let posted = try state.post(
                kind: "deposit",
                idempotencyKey: "intent:\(intentID.uuidString)",
                moves: [
                    Move(.pspClearing, -intent.amountCents),
                    Move(.available, intent.amountCents)
                ]
            )
            state.updateStatement(
                intentID: intentID,
                to: .completed,
                detail: "Added to your Vault",
                ledgerID: posted.id
            )
        }

        save()
        return intent.model
    }

    func cancelDeposit(intentID: UUID) async throws -> DepositIntent {
        guard var intent = state.intents[intentID] else {
            throw VaultError.backend("Unknown payment.")
        }

        guard intent.status == .requiresConfirmation else { return intent.model }

        intent.status = .canceled
        intent.failureReason = "Canceled before payment"
        state.intents[intentID] = intent
        state.updateStatement(intentID: intentID, to: .canceled, detail: intent.failureReason)
        save()
        return intent.model
    }

    // MARK: - Tables

    func registerTable(
        inviteCode: String,
        minimum: Money,
        maximum: Money,
        currencyCode: String
    ) async throws -> TableBuyInLimits {
        let code = inviteCode.uppercased()
        state.tables[code] = StoredTable(
            inviteCode: code,
            currencyCode: currencyCode,
            minCents: minimum.cents,
            maxCents: maximum.cents
        )
        save()
        return TableBuyInLimits(
            inviteCode: code,
            currencyCode: currencyCode,
            minimum: minimum,
            maximum: maximum
        )
    }

    func tableLimits(inviteCode: String) async throws -> TableBuyInLimits? {
        state.tables[inviteCode.uppercased()]?.model
    }

    func buyIn(
        inviteCode: String,
        amount: Money,
        source: TableBuyInSource,
        playerKey: String,
        displayName: String,
        paymentIntentID: UUID?,
        idempotencyKey: String
    ) async throws -> TableBuyInReceipt {
        let code = inviteCode.uppercased()
        guard let table = state.tables[code] else {
            throw VaultError.backend("That table is not open for buy-ins.")
        }
        guard table.model.contains(amount) else {
            throw VaultError.amountOutOfRange(
                "The buy-in must be between \(table.model.minimum.formatted(currencyCode: "USD")) and \(table.model.maximum.formatted(currencyCode: "USD"))."
            )
        }

        let from: AccountKey
        switch source {
        case .vault:
            guard state.balance(.available) >= amount.cents else {
                throw VaultError.insufficientFunds
            }
            from = .available
        case .applePay:
            guard let paymentIntentID, var intent = state.intents[paymentIntentID] else {
                throw VaultError.backend("That buy-in has no payment attached.")
            }
            guard intent.status == .succeeded else {
                throw VaultError.backend("That payment has not been verified yet.")
            }
            guard !intent.consumed else {
                throw VaultError.backend("That payment was already used.")
            }
            guard intent.amountCents == amount.cents,
                  intent.purpose == .tableBuyIn,
                  intent.tableInviteCode == code
            else {
                throw VaultError.backend("That payment does not match this buy-in.")
            }
            intent.consumed = true
            state.intents[paymentIntentID] = intent
            from = .pspClearing
        }

        let kind = source == .vault ? "table_buy_in_vault" : "table_buy_in_direct"
        let inPlay = AccountKey.inPlay(code)
        let posted = try state.post(
            kind: kind,
            idempotencyKey: idempotencyKey,
            moves: [Move(from, -amount.cents), Move(inPlay, amount.cents)]
        )

        var stake = state.stakes[code] ?? StoredStake(playerKey: playerKey, displayName: displayName)
        stake.playerKey = playerKey
        stake.displayName = displayName
        stake.hasLeft = false
        stake.inPlayCents = state.balance(inPlay)
        stake.boughtInCents = state.buyInTotal(for: code)
        state.stakes[code] = stake

        if !state.statement.contains(where: { $0.ledgerID == posted.id }) {
            state.statement.append(
                StoredStatement(
                    kind: source == .vault ? .tableBuyInVault : .tableBuyInDirect,
                    status: .completed,
                    amountCents: source == .vault ? 0 : amount.cents,
                    ledgerID: posted.id,
                    tableInviteCode: code,
                    detail: source == .vault
                        ? "Moved from Available into In Play"
                        : "Paid straight onto the table"
                )
            )
        }

        save()
        return TableBuyInReceipt(
            referenceCode: posted.referenceCode,
            inviteCode: code,
            inPlay: Money(cents: stake.inPlayCents),
            totalBoughtIn: Money(cents: stake.boughtInCents)
        )
    }

    /// Only this device's player has a stake in the sandbox, so this is the one
    /// seat it can answer for. The other seats' chips come from the shared table
    /// row the app already syncs.
    func tableChips(inviteCode: String) async throws -> [TableChipCount] {
        guard let stake = state.stakes[inviteCode.uppercased()], !stake.hasLeft else { return [] }
        return [
            TableChipCount(
                playerKey: stake.playerKey,
                displayName: stake.displayName,
                inPlay: Money(cents: stake.inPlayCents)
            )
        ]
    }

    func recordHand(inviteCode: String, handID: String, deltas: [String: Money]) async throws {
        _ = inviteCode
        _ = handID
        _ = deltas
        throw VaultError.backend("The server records the hand. Send a betting action, not a result.")
    }

    func startHand(inviteCode: String) async throws -> SharedTableHand {
        _ = inviteCode
        throw VaultError.backend("The game is run by the server.")
    }

    func act(
        inviteCode: String,
        action: HandMove,
        amount: Money?,
        actionID: String
    ) async throws -> SharedTableHand {
        _ = inviteCode
        _ = action
        _ = amount
        _ = actionID
        throw VaultError.backend("The game is run by the server.")
    }

    func handView(inviteCode: String) async throws -> SharedTableHand? {
        _ = inviteCode
        return nil
    }

    func leaveTable(inviteCode: String, idempotencyKey: String) async throws -> TableSettlement {
        let code = inviteCode.uppercased()
        guard var stake = state.stakes[code] else {
            throw VaultError.backend("You are not at that table.")
        }

        if stake.hasLeft {
            return TableSettlement(
                inviteCode: code,
                boughtIn: Money(cents: stake.boughtInCents),
                returned: Money(cents: stake.returnedCents),
                referenceCode: "",
                alreadySettled: true
            )
        }

        let inPlay = AccountKey.inPlay(code)
        let finalCents = state.balance(inPlay)
        var referenceCode = ""

        if finalCents > 0 {
            let posted = try state.post(
                kind: "table_return",
                idempotencyKey: idempotencyKey,
                moves: [Move(inPlay, -finalCents), Move(.available, finalCents)]
            )
            referenceCode = posted.referenceCode
            state.statement.append(
                StoredStatement(
                    kind: .tableReturn,
                    status: .completed,
                    amountCents: 0,
                    ledgerID: posted.id,
                    tableInviteCode: code,
                    detail: "Returned from the table to your Vault"
                )
            )
        }

        stake.hasLeft = true
        stake.returnedCents += finalCents
        stake.inPlayCents = 0
        state.stakes[code] = stake
        save()

        return TableSettlement(
            inviteCode: code,
            boughtIn: Money(cents: stake.boughtInCents),
            returned: Money(cents: finalCents),
            referenceCode: referenceCode,
            alreadySettled: false
        )
    }

    // MARK: - Withdrawals

    func requestWithdrawal(amount: Money, idempotencyKey: String) async throws -> WithdrawalRequest {
        if let existing = state.withdrawals.values.first(where: { $0.idempotencyKey == idempotencyKey }) {
            return existing.model
        }

        let summary = try await summary()
        guard amount >= summary.withdrawalMinimum else {
            throw VaultError.amountOutOfRange(
                "The smallest cash-out is \(summary.withdrawalMinimum.formatted(currencyCode: "USD"))."
            )
        }
        guard amount <= summary.withdrawable else {
            throw VaultError.amountOutOfRange(
                "You can cash out at most \(summary.withdrawable.formatted(currencyCode: "USD")) right now."
            )
        }

        let fee = Money(
            cents: summary.withdrawalFeeFlat.cents
                + (amount.cents * summary.withdrawalFeeBasisPoints) / 10_000
        )

        let posted = try state.post(
            kind: "withdrawal_request",
            idempotencyKey: idempotencyKey,
            moves: [Move(.available, -amount.cents), Move(.pendingWithdrawal, amount.cents)]
        )

        let withdrawal = StoredWithdrawal(
            id: UUID(),
            referenceCode: SandboxReference.code("CO"),
            amountCents: amount.cents,
            feeCents: fee.cents,
            status: .pending,
            requestedAt: .now,
            idempotencyKey: idempotencyKey,
            failureReason: nil
        )
        state.withdrawals[withdrawal.id] = withdrawal

        state.statement.append(
            StoredStatement(
                kind: .withdrawalRequest,
                status: .pending,
                amountCents: 0,
                ledgerID: posted.id,
                withdrawalID: withdrawal.id,
                detail: "Cash-out requested"
            )
        )

        save()
        return withdrawal.model
    }

    func withdrawals() async throws -> [WithdrawalRequest] {
        state.withdrawals.values
            .sorted { $0.requestedAt > $1.requestedAt }
            .map(\.model)
    }

    func cancelWithdrawal(id: UUID) async throws -> WithdrawalRequest {
        try resolveWithdrawal(id: id, outcome: .canceled, reason: "You canceled this cash-out")
    }

    func settleWithdrawalInSandbox(id: UUID, succeeds: Bool) async throws -> WithdrawalRequest {
        try resolveWithdrawal(
            id: id,
            outcome: succeeds ? .completed : .failed,
            reason: succeeds ? nil : "Simulated payout failure"
        )
    }

    private func resolveWithdrawal(
        id: UUID,
        outcome: WithdrawalStatus,
        reason: String?
    ) throws -> WithdrawalRequest {
        guard var withdrawal = state.withdrawals[id] else {
            throw VaultError.backend("Unknown cash-out.")
        }
        guard withdrawal.status.isOpen else { return withdrawal.model }

        let posted: StoredLedger
        if outcome == .completed {
            posted = try state.post(
                kind: "withdrawal_completed",
                idempotencyKey: "withdrawal_complete:\(id.uuidString)",
                moves: [
                    Move(.pendingWithdrawal, -withdrawal.amountCents),
                    Move(.payoutClearing, withdrawal.amountCents - withdrawal.feeCents),
                    Move(.fees, withdrawal.feeCents)
                ]
            )
        } else {
            posted = try state.post(
                kind: "withdrawal_\(outcome.rawValue)",
                idempotencyKey: "withdrawal_\(outcome.rawValue):\(id.uuidString)",
                moves: [
                    Move(.pendingWithdrawal, -withdrawal.amountCents),
                    Move(.available, withdrawal.amountCents)
                ]
            )
        }

        withdrawal.status = outcome
        withdrawal.failureReason = reason
        state.withdrawals[id] = withdrawal

        state.updateStatement(withdrawalID: id, to: outcome == .completed ? .completed : .canceled)
        state.statement.append(
            StoredStatement(
                kind: outcome == .completed ? .withdrawalCompleted
                    : outcome == .canceled ? .withdrawalCanceled : .withdrawalFailed,
                status: outcome == .completed ? .completed
                    : outcome == .canceled ? .canceled : .failed,
                amountCents: outcome == .completed ? -withdrawal.amountCents : 0,
                ledgerID: posted.id,
                withdrawalID: id,
                detail: reason ?? "Paid out to \(VaultProviders.payout.destinationDescription)"
            )
        )

        save()
        return withdrawal.model
    }

    // MARK: - Storage

    /// Wipes the demo money. Used when signing out, so the next person to use
    /// the phone does not inherit a balance.
    func reset() {
        state = State()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func load(key: String) -> State? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }

}

/// Mirrors the shape of the reference codes the database hands out, so a demo
/// receipt reads the same as a real one.
private enum SandboxReference {
    static func code(_ prefix: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
        return "\(prefix)-\(formatter.string(from: .now))-\(suffix.uppercased())"
    }
}

// MARK: - Sandbox state

private enum AccountKey: Hashable, Codable {
    case available
    case pendingWithdrawal
    case inPlay(String)
    case pspClearing
    case payoutClearing
    case fees
    /// Stands for everyone else at the table. A hand moves money between seats;
    /// with only one seat on this device the rest of the table is this account,
    /// which keeps every posting balanced.
    case tableCounterparty

    /// Player money. These may never go negative, which is what the real
    /// backend's check constraint enforces.
    var isPlayerHeld: Bool {
        switch self {
        case .available, .pendingWithdrawal, .inPlay: true
        case .pspClearing, .payoutClearing, .fees, .tableCounterparty: false
        }
    }
}

private struct Move {
    let account: AccountKey
    let cents: Int

    init(_ account: AccountKey, _ cents: Int) {
        self.account = account
        self.cents = cents
    }
}

private struct StoredLedger: Codable {
    let id: UUID
    let referenceCode: String
    let kind: String
    let idempotencyKey: String
    let createdAt: Date
}

private struct StoredEntry: Codable {
    let ledgerID: UUID
    let account: AccountKey
    let cents: Int
}

private struct StoredStatement: Codable {
    var id = UUID()
    var referenceCode = SandboxReference.code("PM")
    var kind: VaultTransactionKind
    var status: VaultTransactionStatus
    var amountCents: Int
    var ledgerID: UUID?
    var intentID: UUID?
    var withdrawalID: UUID?
    var tableInviteCode: String?
    var detail: String?
    var createdAt = Date.now

    init(
        kind: VaultTransactionKind,
        status: VaultTransactionStatus,
        amountCents: Int,
        ledgerID: UUID? = nil,
        intentID: UUID? = nil,
        withdrawalID: UUID? = nil,
        tableInviteCode: String? = nil,
        detail: String? = nil
    ) {
        self.kind = kind
        self.status = status
        self.amountCents = amountCents
        self.ledgerID = ledgerID
        self.intentID = intentID
        self.withdrawalID = withdrawalID
        self.tableInviteCode = tableInviteCode
        self.detail = detail
    }

    var model: VaultTransaction {
        VaultTransaction(
            id: id,
            referenceCode: referenceCode,
            kind: kind,
            status: status,
            amount: Money(cents: amountCents),
            currencyCode: "USD",
            tableInviteCode: tableInviteCode,
            isDemo: true,
            detail: detail,
            createdAt: createdAt
        )
    }
}

private struct StoredIntent: Codable {
    let id: UUID
    let referenceCode: String
    let amountCents: Int
    var status: DepositIntentStatus
    let purpose: DepositPurpose
    let tableInviteCode: String?
    let idempotencyKey: String
    var consumed: Bool
    var failureReason: String?

    var model: DepositIntent {
        DepositIntent(
            id: id,
            referenceCode: referenceCode,
            amount: Money(cents: amountCents),
            currencyCode: "USD",
            status: status,
            purpose: purpose,
            tableInviteCode: tableInviteCode,
            isDemo: true,
            failureReason: failureReason
        )
    }
}

private struct StoredWithdrawal: Codable {
    let id: UUID
    let referenceCode: String
    let amountCents: Int
    let feeCents: Int
    var status: WithdrawalStatus
    let requestedAt: Date
    let idempotencyKey: String
    var failureReason: String?

    var model: WithdrawalRequest {
        WithdrawalRequest(
            id: id,
            referenceCode: referenceCode,
            amount: Money(cents: amountCents),
            fee: Money(cents: feeCents),
            net: Money(cents: amountCents - feeCents),
            currencyCode: "USD",
            status: status,
            isDemo: true,
            failureReason: failureReason,
            requestedAt: requestedAt
        )
    }
}

private struct StoredTable: Codable {
    let inviteCode: String
    let currencyCode: String
    let minCents: Int
    let maxCents: Int

    var model: TableBuyInLimits {
        TableBuyInLimits(
            inviteCode: inviteCode,
            currencyCode: currencyCode,
            minimum: Money(cents: minCents),
            maximum: Money(cents: maxCents)
        )
    }
}

private struct StoredStake: Codable {
    var playerKey: String
    var displayName: String
    var boughtInCents = 0
    var inPlayCents = 0
    var returnedCents = 0
    var hasLeft = false
}

private struct State: Codable {
    var ledger: [StoredLedger] = []
    var entries: [StoredEntry] = []
    var statement: [StoredStatement] = []
    var intents: [UUID: StoredIntent] = [:]
    var withdrawals: [UUID: StoredWithdrawal] = [:]
    var tables: [String: StoredTable] = [:]
    var stakes: [String: StoredStake] = [:]

    func balance(_ account: AccountKey) -> Int {
        entries.filter { $0.account == account }.reduce(0) { $0 + $1.cents }
    }

    var inPlayTotal: Int {
        entries.reduce(0) { total, entry in
            if case .inPlay = entry.account { return total + entry.cents }
            return total
        }
    }

    func buyInTotal(for inviteCode: String) -> Int {
        let buyInKinds: Set<String> = ["table_buy_in_vault", "table_buy_in_direct"]
        let buyInIDs = Set(ledger.filter { buyInKinds.contains($0.kind) }.map(\.id))
        return entries
            .filter { $0.account == .inPlay(inviteCode) && buyInIDs.contains($0.ledgerID) }
            .reduce(0) { $0 + $1.cents }
    }

    /// Writes one balanced posting. Same rules as the database function: the
    /// moves must sum to zero, an idempotency key that has been seen before
    /// returns the original posting untouched, and no player account may be left
    /// below zero.
    mutating func post(
        kind: String,
        idempotencyKey: String,
        moves: [Move]
    ) throws -> StoredLedger {
        if let existing = ledger.first(where: { $0.idempotencyKey == idempotencyKey }) {
            return existing
        }

        let applied = moves.filter { $0.cents != 0 }
        guard !applied.isEmpty else { throw VaultError.backend("Nothing to post.") }
        guard applied.reduce(0, { $0 + $1.cents }) == 0 else {
            throw VaultError.backend("Entries do not balance.")
        }

        for move in applied where move.account.isPlayerHeld {
            guard balance(move.account) + move.cents >= 0 else {
                throw VaultError.insufficientFunds
            }
        }

        let posted = StoredLedger(
            id: UUID(),
            referenceCode: SandboxReference.code("TXN"),
            kind: kind,
            idempotencyKey: idempotencyKey,
            createdAt: .now
        )
        ledger.append(posted)
        entries.append(contentsOf: applied.map {
            StoredEntry(ledgerID: posted.id, account: $0.account, cents: $0.cents)
        })
        return posted
    }

    mutating func updateStatement(
        intentID: UUID,
        to status: VaultTransactionStatus,
        detail: String? = nil,
        ledgerID: UUID? = nil
    ) {
        for index in statement.indices where statement[index].intentID == intentID {
            statement[index].status = status
            if let detail { statement[index].detail = detail }
            if let ledgerID { statement[index].ledgerID = ledgerID }
        }
    }

    mutating func updateStatement(withdrawalID: UUID, to status: VaultTransactionStatus) {
        for index in statement.indices
        where statement[index].withdrawalID == withdrawalID
            && statement[index].kind == .withdrawalRequest
            && statement[index].status == .pending {
            statement[index].status = status
        }
    }
}
