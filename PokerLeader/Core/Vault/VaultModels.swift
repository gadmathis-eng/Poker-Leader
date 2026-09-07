import Foundation

/// Everything the owner of a Vault may see about it, and nobody else. This
/// never travels to another player's device: the only figure that leaves is a
/// seat's chips in play, carried by `TableChipCount`.
struct VaultSummary: Equatable, Sendable {
    var currencyCode: String
    var available: Money
    var inPlay: Money
    var pendingDeposits: Money
    var pendingWithdrawals: Money
    var isSandbox: Bool
    var depositMinimum: Money
    var depositMaximum: Money
    var withdrawalMinimum: Money
    var withdrawalFeeFlat: Money
    var withdrawalFeeBasisPoints: Int
    var identityStatus: IdentityStatus
    var payoutMethodStatus: PayoutMethodStatus
    var accountStatus: AccountStatus
    var jurisdictionStatus: JurisdictionStatus
    var selfExcludedUntil: Date?

    /// Everything the player owns, wherever it currently sits.
    var total: Money {
        available + inPlay + pendingDeposits + pendingWithdrawals
    }

    /// Only settled money that is not on a table and not already spoken for by
    /// another cash-out can be withdrawn.
    var withdrawable: Money { available }

    var isSelfExcluded: Bool {
        guard let selfExcludedUntil else { return false }
        return selfExcludedUntil > .now
    }

    var canPlay: Bool {
        accountStatus == .active && jurisdictionStatus != .blocked && !isSelfExcluded
    }

    static let empty = VaultSummary(
        currencyCode: "USD",
        available: .zero,
        inPlay: .zero,
        pendingDeposits: .zero,
        pendingWithdrawals: .zero,
        isSandbox: true,
        depositMinimum: Money(cents: 500),
        depositMaximum: Money(cents: 50_000),
        withdrawalMinimum: Money(cents: 1_000),
        withdrawalFeeFlat: .zero,
        withdrawalFeeBasisPoints: 0,
        identityStatus: .unverified,
        payoutMethodStatus: .none,
        accountStatus: .active,
        jurisdictionStatus: .sandbox,
        selfExcludedUntil: nil
    )
}

enum IdentityStatus: String, Codable, Sendable {
    case unverified, pending, verified, rejected

    var label: String {
        switch self {
        case .unverified: "Not verified"
        case .pending: "Being checked"
        case .verified: "Verified"
        case .rejected: "Could not be verified"
        }
    }
}

enum PayoutMethodStatus: String, Codable, Sendable {
    case none, pending, verified, rejected

    var label: String {
        switch self {
        case .none: "No payout method"
        case .pending: "Being checked"
        case .verified: "Ready"
        case .rejected: "Rejected"
        }
    }
}

enum AccountStatus: String, Codable, Sendable {
    case active, restricted, suspended, closed
}

enum JurisdictionStatus: String, Codable, Sendable {
    case sandbox, allowed, blocked, unknown
}

// MARK: - Statement

/// One line of Transaction History. The immutable ledger underneath is the
/// truth; this is its readable face, and unlike the ledger it carries a status
/// because a deposit is pending before it completes and a cash-out can be
/// rejected after it is asked for.
struct VaultTransaction: Identifiable, Equatable, Sendable {
    let id: UUID
    let referenceCode: String
    let kind: VaultTransactionKind
    let status: VaultTransactionStatus
    /// Signed against the player's total vault. A deposit is positive, a
    /// completed cash-out is negative, and a buy-in that only shifts money from
    /// Available into In Play is zero — the player owns the same amount either
    /// side of it.
    let amount: Money
    let currencyCode: String
    let tableInviteCode: String?
    let isDemo: Bool
    let detail: String?
    let createdAt: Date

    var showsAmount: Bool { !amount.isZero }
}

enum VaultTransactionKind: String, Codable, CaseIterable, Sendable {
    case deposit
    case depositReversed = "deposit_reversed"
    case tableBuyInVault = "table_buy_in_vault"
    case tableBuyInDirect = "table_buy_in_direct"
    case tableWinnings = "table_winnings"
    case tableLoss = "table_loss"
    case tableReturn = "table_return"
    case tableRefund = "table_refund"
    case withdrawalRequest = "withdrawal_request"
    case withdrawalCompleted = "withdrawal_completed"
    case withdrawalRejected = "withdrawal_rejected"
    case withdrawalCanceled = "withdrawal_canceled"
    case withdrawalFailed = "withdrawal_failed"
    case adjustment
    case chargeback

    var title: String {
        switch self {
        case .deposit: "Apple Pay deposit"
        case .depositReversed: "Deposit reversed"
        case .tableBuyInVault: "Table buy-in from Vault"
        case .tableBuyInDirect: "Table buy-in with Apple Pay"
        case .tableWinnings: "Winnings"
        case .tableLoss: "Loss"
        case .tableReturn: "Returned from table"
        case .tableRefund: "Refund"
        case .withdrawalRequest: "Cash-out requested"
        case .withdrawalCompleted: "Withdrawal paid"
        case .withdrawalRejected: "Withdrawal rejected"
        case .withdrawalCanceled: "Withdrawal canceled"
        case .withdrawalFailed: "Withdrawal failed"
        case .adjustment: "Adjustment"
        case .chargeback: "Chargeback"
        }
    }

    var iconName: String {
        switch self {
        case .deposit: "arrow.down.circle.fill"
        case .depositReversed, .chargeback: "arrow.uturn.backward.circle.fill"
        case .tableBuyInVault, .tableBuyInDirect: "suit.spade.fill"
        case .tableWinnings: "arrow.up.right.circle.fill"
        case .tableLoss: "arrow.down.right.circle.fill"
        case .tableReturn, .tableRefund: "arrow.uturn.left.circle.fill"
        case .withdrawalRequest: "clock.arrow.circlepath"
        case .withdrawalCompleted: "arrow.up.circle.fill"
        case .withdrawalRejected, .withdrawalFailed: "xmark.circle.fill"
        case .withdrawalCanceled: "slash.circle.fill"
        case .adjustment: "wrench.and.screwdriver.fill"
        }
    }
}

enum VaultTransactionStatus: String, Codable, Sendable {
    case pending, completed, failed, canceled, rejected, reversed

    var label: String {
        switch self {
        case .pending: "Pending"
        case .completed: "Completed"
        case .failed: "Failed"
        case .canceled: "Canceled"
        case .rejected: "Rejected"
        case .reversed: "Reversed"
        }
    }

    var isSettled: Bool { self == .completed }
    var isUnhappy: Bool { self == .failed || self == .rejected || self == .reversed }
}

// MARK: - Deposits, withdrawals, tables

struct DepositIntent: Identifiable, Equatable, Sendable {
    let id: UUID
    let referenceCode: String
    let amount: Money
    let currencyCode: String
    let status: DepositIntentStatus
    let purpose: DepositPurpose
    let tableInviteCode: String?
    let isDemo: Bool
    let failureReason: String?
}

enum DepositIntentStatus: String, Codable, Sendable {
    case requiresConfirmation = "requires_confirmation"
    case processing, succeeded, failed, canceled, reversed

    var isVerified: Bool { self == .succeeded }
}

enum DepositPurpose: String, Codable, Sendable {
    case vaultDeposit = "vault_deposit"
    case tableBuyIn = "table_buy_in"
}

struct WithdrawalRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let referenceCode: String
    let amount: Money
    let fee: Money
    let net: Money
    let currencyCode: String
    let status: WithdrawalStatus
    let isDemo: Bool
    let failureReason: String?
    let requestedAt: Date
}

enum WithdrawalStatus: String, Codable, Sendable {
    case pending, processing, completed, rejected, canceled, failed

    var label: String {
        switch self {
        case .pending: "Pending"
        case .processing: "On its way"
        case .completed: "Completed"
        case .rejected: "Rejected"
        case .canceled: "Canceled"
        case .failed: "Failed"
        }
    }

    var isOpen: Bool { self == .pending || self == .processing }
}

struct TableBuyInLimits: Equatable, Sendable {
    let inviteCode: String
    let currencyCode: String
    let minimum: Money
    let maximum: Money

    func contains(_ amount: Money) -> Bool {
        amount >= minimum && amount <= maximum
    }
}

/// What one seat is holding. This is the whole of what other players at the
/// table are allowed to know about anybody's money.
struct TableChipCount: Identifiable, Equatable, Sendable {
    var id: String { playerKey }
    let playerKey: String
    let displayName: String
    let inPlay: Money
}

struct TableBuyInReceipt: Equatable, Sendable {
    let referenceCode: String
    let inviteCode: String
    let inPlay: Money
    let totalBoughtIn: Money
}

/// What the player is shown after they stand up: what they sat down with, how
/// it went, and what the backend put back in their Vault.
struct TableSettlement: Equatable, Sendable {
    let inviteCode: String
    let boughtIn: Money
    let returned: Money
    let referenceCode: String
    let alreadySettled: Bool

    var net: Money { returned - boughtIn }
}

enum TableBuyInSource: String, Sendable {
    case vault
    case applePay = "apple_pay"
}

// MARK: - Errors

enum VaultError: LocalizedError, Equatable {
    case notSignedIn
    case notAvailable
    case backend(String)
    case paymentCanceled
    case paymentFailed(String)
    case amountOutOfRange(String)
    case insufficientFunds

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            "Sign in on the You tab to use your Vault."
        case .notAvailable:
            "The Vault is not available right now."
        case .backend(let message):
            message
        case .paymentCanceled:
            "The payment was canceled."
        case .paymentFailed(let message):
            message
        case .amountOutOfRange(let message):
            message
        case .insufficientFunds:
            "Your Vault does not hold that much."
        }
    }

    /// The backend raises exceptions prefixed `vault:`. Everything after the
    /// prefix is written to be read by a player, so it is shown as-is; anything
    /// else is a fault the player cannot act on and gets a generic line.
    static func from(_ error: Error) -> VaultError {
        if let vaultError = error as? VaultError { return vaultError }

        let text = [error.localizedDescription, String(describing: error)]
            .joined(separator: " ")

        guard let range = text.range(of: "vault: ") else {
            if text.lowercased().contains("jwt") || text.lowercased().contains("not signed in") {
                return .notSignedIn
            }
            return .backend("Something went wrong. Try again in a moment.")
        }

        let message = text[range.upperBound...]
            .prefix { $0 != "\"" && $0 != "\n" }
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return .backend(message.isEmpty ? "Something went wrong." : message.capitalizedFirstLetter)
    }
}

private extension String {
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
