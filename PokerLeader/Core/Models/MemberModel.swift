import Foundation
import SwiftData

@Model
final class MemberModel {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var initial: String
    var handle: String?
    var isCurrentUser: Bool
    var joinedAt: Date

    var circle: CircleModel?

    init(
        id: UUID = UUID(),
        displayName: String,
        initial: String,
        handle: String? = nil,
        isCurrentUser: Bool = false,
        joinedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.initial = initial
        self.handle = handle
        self.isCurrentUser = isCurrentUser
        self.joinedAt = joinedAt
    }
}
