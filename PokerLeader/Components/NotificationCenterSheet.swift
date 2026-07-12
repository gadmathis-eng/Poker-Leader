import SwiftData
import SwiftUI

struct NotificationCenterButton: View {
    let unreadCount: Int
    let action: () -> Void

    private let buttonSize: CGFloat = 40
    private let containerSize: CGFloat = 48
    private let bellIconSize: CGFloat = 20
    private let badgeDiameter: CGFloat = 22

    private var badgeGreen: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.42, green: 0.96, blue: 0.62),
                Color(red: 0.22, green: 0.84, blue: 0.48)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var badgeText: String {
        unreadCount > 9 ? "9+" : "\(unreadCount)"
    }

    private var showsBadge: Bool {
        unreadCount > 0
    }

    private var isNinePlus: Bool {
        unreadCount > 9
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                glassBackground
                Image(systemName: "bell")
                    .font(.system(size: bellIconSize, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: buttonSize, height: buttonSize)
            .overlay(alignment: .topTrailing) {
                if showsBadge {
                    notificationBadge
                        .offset(x: 6, y: -4)
                }
            }
            .frame(width: containerSize, height: containerSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Notifications")
        .accessibilityValue(unreadCount > 0 ? "\(unreadCount) unread" : "No unread notifications")
    }

    private var glassBackground: some View {
        Circle()
            .fill(Color(red: 0.15, green: 0.16, blue: 0.18))
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 2)
    }

    @ViewBuilder
    private var notificationBadge: some View {
        Text(badgeText)
            .font(.system(size: isNinePlus ? 11 : 13, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(1)
            .padding(.horizontal, isNinePlus ? 7 : 0)
            .frame(width: isNinePlus ? nil : badgeDiameter, height: badgeDiameter)
            .frame(minWidth: isNinePlus ? 30 : badgeDiameter, minHeight: badgeDiameter)
            .background {
                Group {
                    if isNinePlus {
                        Capsule().fill(badgeGreen)
                    } else {
                        Circle().fill(badgeGreen)
                    }
                }
            }
            .overlay {
                Group {
                    if isNinePlus {
                        Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.75)
                    } else {
                        Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.75)
                    }
                }
            }
            .shadow(color: Color(red: 0.18, green: 0.82, blue: 0.48).opacity(0.55), radius: 4, x: 0, y: 0)
            .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
    }
}

struct NotificationCenterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    let notifications: [AppNotificationModel]
    let onRefresh: () async -> Void

    @State private var actingOnNotificationId: UUID?

    private var visibleNotifications: [AppNotificationModel] {
        notifications.filter { notification in
            if notification.kind == .friendRequest, notification.isHandled {
                return false
            }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleNotifications.isEmpty {
                    ContentUnavailableView(
                        "No notifications",
                        systemImage: "bell.slash",
                        description: Text("Friend requests and finished games will show up here.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(visibleNotifications) { notification in
                                notificationCard(notification)
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(AppTheme.background)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(AppTheme.muted)
                }
                if !visibleNotifications.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Mark all read") {
                            NotificationRepository(context: context).clearAllNotifications()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.positive)
                    }
                }
            }
            .task {
                await onRefresh()
            }
        }
    }

    @ViewBuilder
    private func notificationCard(_ notification: AppNotificationModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName(for: notification.kind))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(iconTint(for: notification.kind))
                    .frame(width: 34, height: 34)
                    .background(iconTint(for: notification.kind).opacity(0.15))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(notification.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.text)
                        Spacer(minLength: 0)
                        if !notification.isRead {
                            Circle()
                                .fill(AppTheme.positive)
                                .frame(width: 8, height: 8)
                        }
                    }

                    Text(notification.message)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(RelativeDateFormatting.playedAgo(from: notification.createdAt))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted.opacity(0.8))
                }
            }

            if notification.kind == .friendRequest, !notification.isHandled {
                HStack(spacing: 10) {
                    Button {
                        respond(to: notification, accept: false)
                    } label: {
                        Text("Decline")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppTheme.card)
                            .foregroundStyle(AppTheme.text)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(actingOnNotificationId == notification.id)

                    Button {
                        respond(to: notification, accept: true)
                    } label: {
                        Text(actingOnNotificationId == notification.id ? "Working..." : "Accept")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppTheme.positive)
                            .foregroundStyle(AppTheme.contrastText)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(actingOnNotificationId == notification.id)
                }
            } else if notification.kind == .gamePlayed, let sessionId = notification.sessionId {
                Button {
                    openSettlement(sessionId: sessionId)
                } label: {
                    Text("View results")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.background)
                        .foregroundStyle(AppTheme.text)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(14)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(notification.isRead ? AppTheme.cardBorder : AppTheme.positive.opacity(0.35))
        )
        .onTapGesture {
            NotificationRepository(context: context).markRead(notification)
        }
    }

    private func iconName(for kind: AppNotificationKind) -> String {
        switch kind {
        case .friendRequest:
            return "person.badge.plus"
        case .gamePlayed:
            return "suit.spade.fill"
        }
    }

    private func iconTint(for kind: AppNotificationKind) -> Color {
        switch kind {
        case .friendRequest:
            return AppTheme.positive
        case .gamePlayed:
            return AppTheme.gold
        }
    }

    private func respond(to notification: AppNotificationModel, accept: Bool) {
        actingOnNotificationId = notification.id
        Task {
            do {
                let repo = NotificationRepository(context: context)
                if accept {
                    try await repo.acceptFriendRequest(notification)
                } else {
                    try await repo.declineFriendRequest(notification)
                }
            } catch {
                actingOnNotificationId = nil
            }
            actingOnNotificationId = nil
        }
    }

    private func openSettlement(sessionId: UUID) {
        if let notification = notifications.first(where: { $0.sessionId == sessionId }) {
            NotificationRepository(context: context).markRead(notification)
        }
        dismiss()
        router.push(.settlement(sessionId))
    }
}
