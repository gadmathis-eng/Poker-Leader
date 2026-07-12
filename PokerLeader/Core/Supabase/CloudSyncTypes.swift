import Foundation

enum SupabaseSyncError: LocalizedError {
    case notConfigured
    case notSignedIn
    case missingCircle
    case nicknameTaken(String)
    case displayNameTaken(String)
    case accountDeletionFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            SupabaseBootstrap.missingConfigurationMessage
        case .notSignedIn:
            "Sign in with Apple, Google, or email to use cloud sync."
        case .missingCircle:
            "This session is not attached to a circle."
        case .nicknameTaken(let handle):
            "\(handle) is already taken. Choose a different username."
        case .displayNameTaken(let name):
            "\(name) is already taken. Choose a different real name."
        case .accountDeletionFailed:
            "We couldn't delete your account right now. Try again in a moment."
        }
    }
}

struct CloudCircleSnapshot {
    let id: UUID
    let name: String
    let shortCode: String
    let defaultBuyIn: Decimal
    let currencyCode: String
    let memberCount: Int
    let gameCount: Int
    let createdAt: Date
    let lastPlayedAt: Date?
    let members: [CloudMemberSnapshot]
}

struct CloudMemberSnapshot {
    let id: UUID
    let displayName: String
    let initial: String
    let handle: String?
    let userId: UUID?
    let isCurrentUser: Bool
    let joinedAt: Date
}

struct CloudSessionSnapshot {
    let id: UUID
    let title: String
    let status: String
    let buyInAmount: Decimal
    let currencyCode: String
    let potTotal: Decimal
    let startedAt: Date?
    let endedAt: Date?
    let summaryLine: String?
    let players: [CloudSessionPlayerSnapshot]
    let payments: [CloudSettlementPaymentSnapshot]
}

struct CloudSessionPlayerSnapshot {
    let id: UUID
    let displayName: String
    let initial: String
    let buyInCount: Int
    let totalIn: Decimal
    let finalOut: Decimal?
    let net: Decimal?
    let memberId: UUID?
}

struct CloudSettlementPaymentSnapshot {
    let id: UUID
    let fromInitial: String
    let fromName: String
    let toInitial: String
    let toName: String
    let amount: Decimal
}

struct CloudCirclePullSnapshot {
    let id: UUID
    let name: String
    let shortCode: String
    let defaultBuyIn: Decimal
    let currencyCode: String
    let memberCount: Int
    let gameCount: Int
    let createdAt: Date
    let lastPlayedAt: Date?
    let isOwner: Bool
    let members: [CloudMemberSnapshot]
    let sessions: [CloudSessionSnapshot]
}

struct CloudUserProfile {
    let userId: String
    let handle: String
    let displayName: String
}

struct CloudIncomingFriendRequest {
    let id: String
    let fromUserId: String
    let fromHandle: String
    let fromDisplayName: String
    let createdAt: Date
    let status: String
}

struct CloudOutgoingFriendRequest {
    let id: String
    let toHandle: String
    let toDisplayName: String
    let status: String
    let createdAt: Date
}
