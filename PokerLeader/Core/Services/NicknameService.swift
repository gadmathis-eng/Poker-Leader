import Foundation
import SwiftData

@MainActor
enum NicknameService {
    static func localReservedHandles(in context: ModelContext, excludingCurrentUser: Bool = true) -> Set<String> {
        guard let circles = try? context.fetch(FetchDescriptor<CircleModel>()) else { return [] }

        let handles = circles.flatMap(\.members).compactMap { member -> String? in
            if excludingCurrentUser && member.isCurrentUser { return nil }
            return MemberModel.normalizedHandle(member.handle)
        }
        return Set(handles)
    }

    static func isNicknameTaken(
        _ handle: String,
        in context: ModelContext,
        excludingCurrentUser: Bool = true
    ) async -> Bool {
        guard let normalized = MemberModel.normalizedHandle(handle) else { return false }
        let lower = normalized.lowercased()

        let localHandles = localReservedHandles(in: context, excludingCurrentUser: excludingCurrentUser)
        if localHandles.contains(where: { $0.lowercased() == lower }) {
            return true
        }

        guard SupabaseBootstrap.isConfigured, SupabaseAuthManager.shared.isSignedIn else { return false }

        if let taken = try? await SupabaseSyncService.shared.isNicknameTaken(
            normalized,
            excludingCurrentUser: excludingCurrentUser
        ) {
            return taken
        }

        return false
    }

    static func generateAvailableLocally(
        for displayName: String,
        in context: ModelContext,
        excludingCurrentUser: Bool = true
    ) -> String {
        let base = MemberModel.handleBase(for: displayName)
        let localHandles = localReservedHandles(in: context, excludingCurrentUser: excludingCurrentUser)

        for suffix in 0..<100 {
            let candidate = suffix == 0 ? "@\(base)" : "@\(base)\(suffix + 1)"
            if !localHandles.contains(where: { $0.lowercased() == candidate.lowercased() }) {
                return candidate
            }
        }

        return MemberModel.generatedUniqueHandle(for: displayName, existingHandles: localHandles)
    }

    static func generateAvailable(
        for displayName: String,
        in context: ModelContext,
        excludingCurrentUser: Bool = true
    ) async -> String {
        let base = MemberModel.handleBase(for: displayName)
        let localHandles = localReservedHandles(in: context, excludingCurrentUser: excludingCurrentUser)

        for suffix in 0..<100 {
            let candidate = suffix == 0 ? "@\(base)" : "@\(base)\(suffix + 1)"
            if localHandles.contains(where: { $0.lowercased() == candidate.lowercased() }) {
                continue
            }
            if await isNicknameTaken(candidate, in: context, excludingCurrentUser: excludingCurrentUser) {
                continue
            }
            return candidate
        }

        return MemberModel.generatedUniqueHandle(for: displayName, existingHandles: localHandles)
    }

    static func validateAvailable(
        _ handle: String,
        in context: ModelContext,
        excludingCurrentUser: Bool = true
    ) async throws {
        guard MemberModel.normalizedHandle(handle) != nil else { return }
        if await isNicknameTaken(handle, in: context, excludingCurrentUser: excludingCurrentUser) {
            throw SupabaseSyncError.nicknameTaken(handle)
        }
    }
}
