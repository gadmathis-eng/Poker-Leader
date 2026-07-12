import Foundation
import SwiftData

@MainActor
enum DisplayNameService {
    static func normalized(_ displayName: String) -> String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func localReservedDisplayNames(
        in context: ModelContext,
        excludingCurrentUser: Bool = true
    ) -> Set<String> {
        guard let circles = try? context.fetch(FetchDescriptor<CircleModel>()) else { return [] }

        let names = circles.flatMap(\.members).compactMap { member -> String? in
            if excludingCurrentUser && member.isCurrentUser { return nil }
            let cleaned = normalized(member.displayName)
            if MemberModel.isPlaceholderName(cleaned) { return nil }
            return cleaned.lowercased()
        }
        return Set(names)
    }

    static func isDisplayNameTaken(
        _ displayName: String,
        in context: ModelContext,
        excludingCurrentUser: Bool = true
    ) async -> Bool {
        let cleaned = normalized(displayName)
        guard !cleaned.isEmpty, !MemberModel.isPlaceholderName(cleaned) else { return false }
        let lower = cleaned.lowercased()

        if localReservedDisplayNames(in: context, excludingCurrentUser: excludingCurrentUser).contains(lower) {
            return true
        }

        guard SupabaseBootstrap.isConfigured, SupabaseAuthManager.shared.isSignedIn else { return false }

        if let taken = try? await SupabaseSyncService.shared.isDisplayNameTaken(
            cleaned,
            excludingCurrentUser: excludingCurrentUser
        ) {
            return taken
        }

        return false
    }

    static func validateAvailable(
        _ displayName: String,
        in context: ModelContext,
        excludingCurrentUser: Bool = true
    ) async throws {
        let cleaned = normalized(displayName)
        guard !cleaned.isEmpty, !MemberModel.isPlaceholderName(cleaned) else { return }
        if await isDisplayNameTaken(cleaned, in: context, excludingCurrentUser: excludingCurrentUser) {
            throw SupabaseSyncError.displayNameTaken(cleaned)
        }
    }
}
