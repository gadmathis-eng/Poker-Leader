import Foundation
import SwiftData

@MainActor
enum AccountSessionCoordinator {
    static func signOut(context: ModelContext, router: AppRouter) async {
        if SupabaseBootstrap.isConfigured {
            try? await SupabaseAuthManager.shared.signOut()
        }
        resetLocalSession(context: context, router: router)
    }

    static func deleteAccount(context: ModelContext, router: AppRouter) async throws {
        if SupabaseBootstrap.isConfigured, SupabaseAuthManager.shared.isSignedIn {
            do {
                try await SupabaseAuthManager.shared.deleteAccount()
            } catch {
                throw SupabaseSyncError.accountDeletionFailed
            }
        }
        resetLocalSession(context: context, router: router)
    }

    static func resetLocalSession(context: ModelContext, router: AppRouter) {
        clearLocalData(context: context)
        resetProfileDefaults()
        clearAccountStores()
        router.popToRoot()
        router.selectedCircleId = nil
        router.currentUserMemberId = nil
    }

    static func restoreProfileFromCloudIfAvailable() async {
        guard SupabaseBootstrap.isConfigured, SupabaseAuthManager.shared.isSignedIn else { return }

        guard let profile = try? await SupabaseSyncService.shared.fetchCurrentUserProfile() else { return }

        UserDefaults.standard.set(profile.displayName, forKey: "displayName")
        UserDefaults.standard.set(profile.handle, forKey: "playerHandle")
    }

    private static func clearLocalData(context: ModelContext) {
        deleteAll(CircleModel.self, in: context)
        deleteAll(FriendRequestModel.self, in: context)
        deleteAll(AppNotificationModel.self, in: context)
        try? context.save()
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) {
        guard let items = try? context.fetch(FetchDescriptor<T>()) else { return }
        for item in items {
            context.delete(item)
        }
    }

    private static func resetProfileDefaults() {
        UserDefaults.standard.set("Your name", forKey: "displayName")
        UserDefaults.standard.set("@yourname", forKey: "playerHandle")
    }

    private static func clearAccountStores() {
        DeletedCirclesStore.clearAll()
        CircleCreatorStore.clearAll()
        CircleOrderStore.clearAll()
        UserDefaults.standard.removeObject(forKey: "dismissedNotificationKeys")
    }
}
