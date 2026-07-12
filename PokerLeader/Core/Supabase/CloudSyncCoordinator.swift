import Foundation
import SwiftData

@MainActor
enum CloudSyncCoordinator {
    static func restoreAccountAndSync(context: ModelContext) async {
        guard SupabaseBootstrap.isConfigured else { return }
        await SupabaseAuthManager.shared.refreshSession()
        guard SupabaseAuthManager.shared.isSignedIn else { return }

        await AccountSessionCoordinator.restoreProfileFromCloudIfAvailable()

        let displayName = UserDefaults.standard.string(forKey: "displayName") ?? "Your name"
        let playerHandle = UserDefaults.standard.string(forKey: "playerHandle") ?? "@yourname"
        await syncAll(context: context, displayName: displayName, playerHandle: playerHandle)
    }

    static func syncAll(
        context: ModelContext,
        displayName: String,
        playerHandle: String
    ) async {
        guard SupabaseBootstrap.isConfigured else { return }
        await SupabaseAuthManager.shared.refreshSession()
        guard SupabaseAuthManager.shared.isSignedIn else { return }

        let circleRepository = CircleRepository(context: context)
        let notificationRepository = NotificationRepository(context: context)

        do {
            try await circleRepository.syncFromCloud(
                displayName: displayName,
                playerHandle: playerHandle
            )
        } catch {
            return
        }

        let circles = (try? circleRepository.fetchAll()) ?? []
        notificationRepository.syncGamePlayedNotifications(in: circles)
        await notificationRepository.syncIncomingFriendRequests()
        await notificationRepository.syncOutgoingFriendRequests()
    }
}
