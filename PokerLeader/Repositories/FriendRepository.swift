import Foundation
import SwiftData

enum FriendError: LocalizedError {
    case invalidHandle
    case cannotAddSelf
    case userNotFound
    case alreadyRequested
    case cloudSyncRequired

    var errorDescription: String? {
        switch self {
        case .invalidHandle:
            return "Enter a valid nickname, like @lucky."
        case .cannotAddSelf:
            return "You cannot send a friend request to yourself."
        case .userNotFound:
            return "No player found with that nickname."
        case .alreadyRequested:
            return "You already sent a request to this player."
        case .cloudSyncRequired:
            return "Cloud sync is required to send friend requests."
        }
    }
}

@MainActor
final class FriendRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func pendingRequests() throws -> [FriendRequestModel] {
        let descriptor = FetchDescriptor<FriendRequestModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).filter { $0.status == .pending || $0.status == .sent }
    }

    func sendRequest(
        targetHandle: String,
        senderHandle: String,
        senderDisplayName: String
    ) async throws -> FriendRequestModel {
        guard let normalizedTarget = MemberModel.normalizedHandle(targetHandle) else {
            throw FriendError.invalidHandle
        }

        guard let normalizedSender = MemberModel.normalizedHandle(senderHandle) else {
            throw FriendError.invalidHandle
        }

        guard normalizedTarget.lowercased() != normalizedSender.lowercased() else {
            throw FriendError.cannotAddSelf
        }

        let existing = try pendingRequests()
        if existing.contains(where: { $0.targetHandle.lowercased() == normalizedTarget.lowercased() }) {
            throw FriendError.alreadyRequested
        }

        guard SupabaseBootstrap.isConfigured else {
            throw FriendError.cloudSyncRequired
        }

        guard SupabaseAuthManager.shared.isSignedIn else {
            throw SupabaseSyncError.notSignedIn
        }

        let service = SupabaseSyncService.shared
        let userId = try await service.ensureReady()
        try await service.upsertUserProfile(handle: normalizedSender, displayName: senderDisplayName)

        guard let target = try await service.findUserProfile(handle: normalizedTarget) else {
            throw FriendError.userNotFound
        }

        let requestId = try await service.sendFriendRequest(
            to: target,
            fromUserId: userId,
            fromHandle: normalizedSender,
            fromDisplayName: senderDisplayName
        )

        let request = FriendRequestModel(
            targetHandle: normalizedTarget,
            targetDisplayName: target.displayName,
            status: .sent,
            cloudRequestId: requestId
        )
        context.insert(request)
        try context.save()
        return request
    }
}
