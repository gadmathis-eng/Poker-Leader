import Foundation
import SwiftData

@MainActor
final class NotificationRepository {
    private static let dismissedKeysDefaultsKey = "dismissedNotificationKeys"

    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    private var dismissedKeys: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.dismissedKeysDefaultsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.dismissedKeysDefaultsKey) }
    }

    func allNotifications() throws -> [AppNotificationModel] {
        let descriptor = FetchDescriptor<AppNotificationModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func unreadCount() throws -> Int {
        try allNotifications().filter { !$0.isRead && !$0.isHandled }.count
    }

    func markRead(_ notification: AppNotificationModel) {
        notification.isRead = true
        try? context.save()
    }

    func markAllAsSeen() {
        guard let notifications = try? allNotifications() else { return }
        for notification in notifications where !notification.isHandled {
            notification.isRead = true
        }
        try? context.save()
    }

    func clearAllNotifications() {
        guard let notifications = try? allNotifications() else { return }
        var dismissed = dismissedKeys

        for notification in notifications {
            if let key = persistenceKey(for: notification) {
                dismissed.insert(key)
            }
            context.delete(notification)
        }

        dismissedKeys = dismissed
        try? context.save()
    }

    func createGamePlayedNotificationIfNeeded(
        session: SessionModel,
        net: Decimal,
        circleName: String
    ) {
        let externalId = session.id.uuidString
        if isDismissed(kind: .gamePlayed, externalId: externalId) || notificationExists(externalId: externalId, kind: .gamePlayed) {
            return
        }

        let netText = MoneyFormatting.format(net, currencyCode: session.currencyCode)
        let notification = AppNotificationModel(
            kind: .gamePlayed,
            title: "Game finished",
            message: "\(session.title) in \(circleName) · \(netText)",
            createdAt: session.endedAt ?? .now,
            sessionId: session.id
        )
        context.insert(notification)
        try? context.save()
    }

    func syncGamePlayedNotifications(in circles: [CircleModel]) {
        let memberIds = Set(circles.flatMap(\.members).filter(\.isCurrentUser).map(\.id))

        for circle in circles {
            for session in circle.sessions where session.status == .settled {
                guard !notificationExists(externalId: session.id.uuidString, kind: .gamePlayed) else {
                    continue
                }

                guard let player = session.players.first(where: { player in
                    guard let memberId = player.memberId else { return false }
                    return memberIds.contains(memberId)
                }) else {
                    continue
                }

                createGamePlayedNotificationIfNeeded(
                    session: session,
                    net: player.net ?? 0,
                    circleName: circle.name
                )
            }
        }
    }

    func syncIncomingFriendRequests() async {
        guard SupabaseBootstrap.isConfigured else { return }

        do {
            let requests = try await SupabaseSyncService.shared.fetchIncomingFriendRequests()
            for request in requests {
                guard
                    !isDismissed(kind: .friendRequest, externalId: request.id),
                    !notificationExists(externalId: request.id, kind: .friendRequest)
                else {
                    continue
                }

                let notification = AppNotificationModel(
                    kind: .friendRequest,
                    title: "Friend request",
                    message: "\(request.fromDisplayName) (\(request.fromHandle)) wants to be friends.",
                    createdAt: request.createdAt,
                    externalId: request.id,
                    senderHandle: request.fromHandle,
                    senderDisplayName: request.fromDisplayName
                )
                context.insert(notification)
            }
            try? context.save()
        } catch {
            return
        }
    }

    func syncOutgoingFriendRequests() async {
        guard SupabaseBootstrap.isConfigured, SupabaseAuthManager.shared.isSignedIn else { return }

        do {
            let requests = try await SupabaseSyncService.shared.fetchOutgoingFriendRequests()
            let descriptor = FetchDescriptor<FriendRequestModel>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let localRequests = try context.fetch(descriptor)

            for remote in requests where remote.status != "pending" {
                guard let match = localRequests.first(where: {
                    $0.cloudRequestId == remote.id
                        || $0.targetHandle.lowercased() == remote.toHandle.lowercased()
                }) else {
                    continue
                }

                switch remote.status {
                case "accepted":
                    match.status = .accepted
                case "declined":
                    match.status = .declined
                default:
                    break
                }
            }

            try? context.save()
        } catch {
            return
        }
    }

    func acceptFriendRequest(_ notification: AppNotificationModel) async throws {
        guard
            notification.kind == .friendRequest,
            let requestId = notification.externalId
        else {
            return
        }

        try await SupabaseSyncService.shared.respondToFriendRequest(requestId: requestId, accept: true)
        notification.isHandled = true
        notification.isRead = true
        notification.message = "You accepted \(notification.senderDisplayName ?? "this player")'s friend request."
        try context.save()
    }

    func declineFriendRequest(_ notification: AppNotificationModel) async throws {
        guard
            notification.kind == .friendRequest,
            let requestId = notification.externalId
        else {
            return
        }

        try await SupabaseSyncService.shared.respondToFriendRequest(requestId: requestId, accept: false)
        notification.isHandled = true
        notification.isRead = true
        notification.message = "You declined \(notification.senderDisplayName ?? "this player")'s friend request."
        try context.save()
    }

    private func notificationExists(externalId: String, kind: AppNotificationKind) -> Bool {
        guard let notifications = try? allNotifications() else { return false }
        return notifications.contains { $0.externalId == externalId && $0.kind == kind }
    }

    private func persistenceKey(for notification: AppNotificationModel) -> String? {
        if let externalId = notification.externalId {
            return dismissalKey(kind: notification.kind, externalId: externalId)
        }

        if let sessionId = notification.sessionId {
            return dismissalKey(kind: notification.kind, externalId: sessionId.uuidString)
        }

        return nil
    }

    private func dismissalKey(kind: AppNotificationKind, externalId: String) -> String {
        "\(kind.rawValue):\(externalId)"
    }

    private func isDismissed(kind: AppNotificationKind, externalId: String) -> Bool {
        dismissedKeys.contains(dismissalKey(kind: kind, externalId: externalId))
    }
}
