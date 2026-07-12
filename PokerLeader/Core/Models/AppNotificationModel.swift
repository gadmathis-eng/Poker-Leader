import Foundation
import SwiftData

enum AppNotificationKind: String, Codable {
    case friendRequest
    case gamePlayed
}

@Model
final class AppNotificationModel {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var title: String
    var message: String
    var createdAt: Date
    var isRead: Bool
    var externalId: String?
    var senderHandle: String?
    var senderDisplayName: String?
    var sessionId: UUID?
    var isHandled: Bool

    var kind: AppNotificationKind {
        get { AppNotificationKind(rawValue: kindRaw) ?? .gamePlayed }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        kind: AppNotificationKind,
        title: String,
        message: String,
        createdAt: Date = .now,
        isRead: Bool = false,
        externalId: String? = nil,
        senderHandle: String? = nil,
        senderDisplayName: String? = nil,
        sessionId: UUID? = nil,
        isHandled: Bool = false
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.title = title
        self.message = message
        self.createdAt = createdAt
        self.isRead = isRead
        self.externalId = externalId
        self.senderHandle = senderHandle
        self.senderDisplayName = senderDisplayName
        self.sessionId = sessionId
        self.isHandled = isHandled
    }
}
