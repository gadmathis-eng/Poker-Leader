import Foundation
import SwiftData

@Model
final class CircleModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var shortCode: String
    var defaultBuyIn: Decimal {
        didSet { defaultBuyIn = defaultBuyIn.clampedToNonNegative }
    }
    var currencyCode: String
    var memberCount: Int
    var gameCount: Int
    var createdAt: Date
    var lastPlayedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \MemberModel.circle)
    var members: [MemberModel]

    @Relationship(deleteRule: .cascade, inverse: \SessionModel.circle)
    var sessions: [SessionModel]

    init(
        id: UUID = UUID(),
        name: String,
        shortCode: String,
        defaultBuyIn: Decimal = 20,
        currencyCode: String = "GBP",
        memberCount: Int = 0,
        gameCount: Int = 0,
        createdAt: Date = .now,
        lastPlayedAt: Date? = nil,
        members: [MemberModel] = [],
        sessions: [SessionModel] = []
    ) {
        self.id = id
        self.name = name
        self.shortCode = shortCode
        self.defaultBuyIn = defaultBuyIn.clampedToNonNegative
        self.currencyCode = currencyCode
        self.memberCount = memberCount
        self.gameCount = gameCount
        self.createdAt = createdAt
        self.lastPlayedAt = lastPlayedAt
        self.members = members
        self.sessions = sessions
    }
}
