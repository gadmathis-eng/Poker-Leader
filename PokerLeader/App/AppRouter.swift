import Foundation
import SwiftUI

enum AppRoute: Hashable {
    case circleDetail(UUID)
    case newSession(UUID)
    case liveTable(UUID)
    case finalStacks(UUID)
    case confirmation(UUID)
    case settlement(UUID)
    case shareSettlement(UUID)
    case playerProfile(UUID)
    case headToHead(UUID, UUID)
}

@Observable
@MainActor
final class AppRouter {
    var circlesPath = NavigationPath()
    var selectedCircleId: UUID?
    var currentUserMemberId: UUID?
    var pendingInviteCode: String?
    var pendingSettlementSessionId: UUID?
    var pendingTableInviteCode: String?

    func push(_ route: AppRoute) {
        circlesPath.append(route)
    }

    func popToRoot() {
        circlesPath = NavigationPath()
    }

    func handleDeepLink(_ url: URL) -> Bool {
        if handleTableInviteURL(url) {
            return true
        }

        if handleInviteURL(url) {
            return true
        }

        guard let sessionId = CircleInviteDeepLink.settlementSessionId(from: url) else {
            return false
        }

        pendingSettlementSessionId = sessionId
        return true
    }

    func handleInviteURL(_ url: URL) -> Bool {
        guard let code = CircleInviteDeepLink.inviteCode(from: url) else { return false }
        pendingInviteCode = code
        return true
    }

    func handleTableInviteURL(_ url: URL) -> Bool {
        guard let code = TableInviteDeepLink.inviteCode(from: url) else { return false }
        pendingTableInviteCode = code
        return true
    }
}
