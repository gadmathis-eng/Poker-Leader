import Foundation
import SwiftData

enum FriendRequestStatus: String, Codable {
    case pending
    case sent
    case accepted
    case declined
}

@Model
final class FriendRequestModel {
    @Attribute(.unique) var id: UUID
    var targetHandle: String
    var targetDisplayName: String?
    var statusRaw: String
    var cloudRequestId: String?
    var createdAt: Date

    var status: FriendRequestStatus {
        get { FriendRequestStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        targetHandle: String,
        targetDisplayName: String? = nil,
        status: FriendRequestStatus = .pending,
        cloudRequestId: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.targetHandle = targetHandle
        self.targetDisplayName = targetDisplayName
        self.statusRaw = status.rawValue
        self.cloudRequestId = cloudRequestId
        self.createdAt = createdAt
    }
}
