import Foundation
import Supabase

@MainActor
final class SupabaseSyncService {
    static let shared = SupabaseSyncService()

    private init() {}

    var isReady: Bool {
        SupabaseBootstrap.isConfigured
    }

    @discardableResult
    func ensureReady() async throws -> String {
        let client = try SupabaseBootstrap.requireClient()

        if let session = try? await client.auth.session {
            return session.user.id.uuidString
        }

        throw SupabaseSyncError.notSignedIn
    }

    func fetchCirclesForCurrentUser() async throws -> [CloudCirclePullSnapshot] {
        let userId = try await ensureReady()
        guard let currentUserUUID = UUID(uuidString: userId) else {
            throw SupabaseSyncError.notSignedIn
        }

        let client = try SupabaseBootstrap.requireClient()

        let ownedRows: [CircleWithMembersRow] = try await client
            .from("circles")
            .select("*, circle_members(*)")
            .eq("owner_user_id", value: userId)
            .execute()
            .value

        let memberships: [CircleMembershipRow] = try await client
            .from("circle_members")
            .select("circle_id")
            .eq("user_id", value: userId)
            .execute()
            .value

        let ownedIds = Set(ownedRows.map(\.id))
        let memberOnlyIds = Set(memberships.map(\.circleId)).subtracting(ownedIds)

        var memberRows: [CircleWithMembersRow] = []
        if !memberOnlyIds.isEmpty {
            memberRows = try await client
                .from("circles")
                .select("*, circle_members(*)")
                .in("id", values: memberOnlyIds.map(\.uuidString))
                .execute()
                .value
        }

        var snapshots: [CloudCirclePullSnapshot] = []
        for row in ownedRows {
            let sessionRows: [SessionPayloadRow] = try await client
                .from("sessions")
                .select()
                .eq("circle_id", value: row.id.uuidString)
                .execute()
                .value

            snapshots.append(row.pullSnapshot(currentUserId: currentUserUUID, isOwner: true, sessions: sessionRows))
        }

        for row in memberRows {
            let sessionRows: [SessionPayloadRow] = try await client
                .from("sessions")
                .select()
                .eq("circle_id", value: row.id.uuidString)
                .execute()
                .value

            snapshots.append(row.pullSnapshot(currentUserId: currentUserUUID, isOwner: false, sessions: sessionRows))
        }

        return snapshots
    }

    func upsertCircle(_ circle: CircleModel) async throws {
        let userId = try await ensureReady()
        let client = try SupabaseBootstrap.requireClient()

        let row = CircleRow(
            id: circle.id,
            ownerUserId: UUID(uuidString: userId),
            name: circle.name,
            shortCode: circle.shortCode.uppercased(),
            defaultBuyIn: circle.defaultBuyIn.cloudString,
            currencyCode: circle.currencyCode,
            memberCount: circle.members.count,
            gameCount: circle.gameCount,
            createdAt: circle.createdAt,
            lastPlayedAt: circle.lastPlayedAt,
            updatedAt: .now
        )

        try await client.from("circles").upsert(row).execute()

        for member in circle.members {
            try await upsertMember(member, in: circle)
        }

        for session in circle.sessions {
            try await upsertSession(session)
        }
    }

    func upsertMember(_ member: MemberModel, in circle: CircleModel) async throws {
        let userId = try await ensureReady()
        let client = try SupabaseBootstrap.requireClient()

        let row = CircleMemberRow(
            id: member.id,
            circleId: circle.id,
            userId: member.isCurrentUser ? UUID(uuidString: userId) : nil,
            displayName: member.displayName,
            initial: member.initial.uppercased(),
            handle: member.handle,
            isCurrentUser: member.isCurrentUser,
            joinedAt: member.joinedAt,
            updatedAt: .now
        )

        try await client.from("circle_members").upsert(row).execute()
        try await client
            .from("circles")
            .update(CircleSummaryUpdate(memberCount: circle.members.count, updatedAt: .now))
            .eq("id", value: circle.id.uuidString)
            .execute()
    }

    func upsertSession(_ session: SessionModel) async throws {
        guard let circle = session.circle else {
            throw SupabaseSyncError.missingCircle
        }

        _ = try await ensureReady()
        let client = try SupabaseBootstrap.requireClient()

        let row = SessionRow(
            id: session.id,
            circleId: circle.id,
            title: session.title,
            status: session.status.rawValue,
            buyInAmount: session.buyInAmount.cloudString,
            currencyCode: session.currencyCode,
            potTotal: session.potTotal.cloudString,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            summaryLine: session.summaryLine,
            players: session.players.map(\.cloudPayload),
            payments: session.payments.map(\.cloudPayload),
            updatedAt: .now
        )

        try await client.from("sessions").upsert(row).execute()
        try await client
            .from("circles")
            .update(
                CircleActivityUpdate(
                    gameCount: circle.gameCount,
                    lastPlayedAt: circle.lastPlayedAt,
                    updatedAt: .now
                )
            )
            .eq("id", value: circle.id.uuidString)
            .execute()
    }

    func deleteCircle(id: UUID) async throws {
        _ = try await ensureReady()
        let client = try SupabaseBootstrap.requireClient()
        try await client.from("circles").delete().eq("id", value: id.uuidString).execute()
    }

    func leaveCircle(circleId: UUID) async throws {
        let userId = try await ensureReady()
        let client = try SupabaseBootstrap.requireClient()
        try await client
            .from("circle_members")
            .delete()
            .eq("circle_id", value: circleId.uuidString)
            .eq("user_id", value: userId)
            .execute()
    }

    func deleteCurrentUserAccount() async throws {
        _ = try await ensureReady()
        let client = try SupabaseBootstrap.requireClient()
        try await client.rpc("delete_own_account").execute()
    }

    func upsertUserProfile(handle: String, displayName: String) async throws {
        let userId = try await ensureReady()
        guard let normalizedHandle = MemberModel.normalizedHandle(handle) else { return }
        let cleanedDisplayName = DisplayNameService.normalized(displayName)

        if try await isNicknameTaken(normalizedHandle, excludingCurrentUser: true) {
            throw SupabaseSyncError.nicknameTaken(normalizedHandle)
        }

        if try await isDisplayNameTaken(cleanedDisplayName, excludingCurrentUser: true) {
            throw SupabaseSyncError.displayNameTaken(cleanedDisplayName)
        }

        let client = try SupabaseBootstrap.requireClient()
        let row = ProfileUpsertRow(
            id: UUID(uuidString: userId)!,
            handle: normalizedHandle,
            handleLower: normalizedHandle.lowercased(),
            displayName: cleanedDisplayName,
            displayNameLower: cleanedDisplayName.lowercased(),
            updatedAt: .now
        )

        do {
            try await client.from("profiles").upsert(row).execute()
        } catch {
            try await client.from("profiles").upsert(row.legacyFallback).execute()
        }
    }

    func isDisplayNameTaken(_ displayName: String, excludingCurrentUser: Bool = true) async throws -> Bool {
        _ = try await ensureReady()
        let cleanedDisplayName = DisplayNameService.normalized(displayName)
        guard !cleanedDisplayName.isEmpty, !MemberModel.isPlaceholderName(cleanedDisplayName) else { return false }

        let client = try SupabaseBootstrap.requireClient()
        let lower = cleanedDisplayName.lowercased()
        let rows = try await matchingProfiles(forDisplayNameLower: lower, client: client)

        guard let row = rows.first else { return false }

        if excludingCurrentUser,
           let userId = SupabaseAuthManager.shared.userId,
           row.id.uuidString == userId {
            return false
        }

        return true
    }

    private func matchingProfiles(forDisplayNameLower lower: String, client: SupabaseClient) async throws -> [ProfileRow] {
        if let rows: [ProfileRow] = try? await client
            .from("profiles")
            .select()
            .eq("display_name_lower", value: lower)
            .limit(1)
            .execute()
            .value,
           !rows.isEmpty {
            return rows
        }

        return []
    }

    func isNicknameTaken(_ handle: String, excludingCurrentUser: Bool = true) async throws -> Bool {
        guard let normalizedHandle = MemberModel.normalizedHandle(handle) else { return false }
        guard let profile = try await findUserProfile(handle: normalizedHandle) else { return false }

        if excludingCurrentUser,
           let userId = SupabaseAuthManager.shared.userId,
           profile.userId == userId {
            return false
        }

        return true
    }

    func fetchCurrentUserProfile() async throws -> CloudUserProfile? {
        let userId = try await ensureReady()
        let client = try SupabaseBootstrap.requireClient()

        let rows: [ProfileRow] = try await client
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value

        guard let row = rows.first else { return nil }
        return CloudUserProfile(
            userId: row.id.uuidString,
            handle: row.handle,
            displayName: row.displayName
        )
    }

    func findUserProfile(handle: String) async throws -> CloudUserProfile? {
        _ = try await ensureReady()
        guard let normalizedHandle = MemberModel.normalizedHandle(handle) else { return nil }

        let client = try SupabaseBootstrap.requireClient()
        let rows: [ProfileRow] = try await client
            .from("profiles")
            .select()
            .eq("handle_lower", value: normalizedHandle.lowercased())
            .limit(1)
            .execute()
            .value

        guard let row = rows.first else { return nil }
        return CloudUserProfile(
            userId: row.id.uuidString,
            handle: row.handle,
            displayName: row.displayName
        )
    }

    func sendFriendRequest(
        to target: CloudUserProfile,
        fromUserId: String,
        fromHandle: String,
        fromDisplayName: String
    ) async throws -> String {
        _ = try await ensureReady()
        let client = try SupabaseBootstrap.requireClient()
        let requestId = UUID()

        let row = FriendRequestRow(
            id: requestId,
            fromUserId: UUID(uuidString: fromUserId)!,
            fromHandle: fromHandle,
            fromDisplayName: fromDisplayName,
            toUserId: UUID(uuidString: target.userId)!,
            toHandle: target.handle,
            status: "pending",
            createdAt: .now,
            respondedAt: nil
        )

        try await client.from("friend_requests").insert(row).execute()
        return requestId.uuidString
    }

    func fetchIncomingFriendRequests() async throws -> [CloudIncomingFriendRequest] {
        let userId = try await ensureReady()
        let client = try SupabaseBootstrap.requireClient()

        let rows: [FriendRequestRow] = try await client
            .from("friend_requests")
            .select()
            .eq("to_user_id", value: userId)
            .eq("status", value: "pending")
            .execute()
            .value

        return rows.map {
            CloudIncomingFriendRequest(
                id: $0.id.uuidString,
                fromUserId: $0.fromUserId.uuidString,
                fromHandle: $0.fromHandle,
                fromDisplayName: $0.fromDisplayName,
                createdAt: $0.createdAt,
                status: $0.status
            )
        }
    }

    func respondToFriendRequest(requestId: String, accept: Bool) async throws {
        _ = try await ensureReady()
        let client = try SupabaseBootstrap.requireClient()
        let status = accept ? "accepted" : "declined"

        try await client
            .from("friend_requests")
            .update(FriendRequestResponseUpdate(status: status, respondedAt: .now))
            .eq("id", value: requestId)
            .execute()
    }

    func fetchOutgoingFriendRequests() async throws -> [CloudOutgoingFriendRequest] {
        let userId = try await ensureReady()
        let client = try SupabaseBootstrap.requireClient()

        let rows: [FriendRequestRow] = try await client
            .from("friend_requests")
            .select()
            .eq("from_user_id", value: userId)
            .execute()
            .value

        return rows.map {
            CloudOutgoingFriendRequest(
                id: $0.id.uuidString,
                toHandle: $0.toHandle,
                toDisplayName: $0.toHandle,
                status: $0.status,
                createdAt: $0.createdAt
            )
        }
    }

    func fetchCircle(inviteCode: String) async throws -> CloudCircleSnapshot? {
        _ = try await ensureReady()
        let normalized = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let client = try SupabaseBootstrap.requireClient()

        let rows: [CircleWithMembersRow] = try await client
            .from("circles")
            .select("*, circle_members(*)")
            .eq("short_code", value: normalized)
            .limit(1)
            .execute()
            .value

        guard let row = rows.first else { return nil }
        return row.snapshot
    }
}

// MARK: - Database rows

private struct CircleMembershipRow: Decodable {
    let circleId: UUID

    enum CodingKeys: String, CodingKey {
        case circleId = "circle_id"
    }
}

private struct SessionPayloadRow: Decodable {
    let id: UUID
    let circleId: UUID
    let title: String
    let status: String
    let buyInAmount: String
    let currencyCode: String
    let potTotal: String
    let startedAt: Date?
    let endedAt: Date?
    let summaryLine: String?
    let players: [SessionPlayerPayload]
    let payments: [SettlementPaymentPayload]

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case title
        case status
        case buyInAmount = "buy_in_amount"
        case currencyCode = "currency_code"
        case potTotal = "pot_total"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case summaryLine = "summary_line"
        case players
        case payments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        circleId = try container.decode(UUID.self, forKey: .circleId)
        title = try container.decode(String.self, forKey: .title)
        status = try container.decode(String.self, forKey: .status)
        buyInAmount = try container.decodeIfPresent(String.self, forKey: .buyInAmount) ?? "0"
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? CurrencyPreferences.defaultCurrencyCode
        potTotal = try container.decodeIfPresent(String.self, forKey: .potTotal) ?? "0"
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        summaryLine = try container.decodeIfPresent(String.self, forKey: .summaryLine)
        players = try container.decodeIfPresent([SessionPlayerPayload].self, forKey: .players) ?? []
        payments = try container.decodeIfPresent([SettlementPaymentPayload].self, forKey: .payments) ?? []
    }

    var snapshot: CloudSessionSnapshot {
        CloudSessionSnapshot(
            id: id,
            title: title,
            status: status,
            buyInAmount: Decimal(string: buyInAmount) ?? 0,
            currencyCode: currencyCode,
            potTotal: Decimal(string: potTotal) ?? 0,
            startedAt: startedAt,
            endedAt: endedAt,
            summaryLine: summaryLine,
            players: players.map(\.cloudSnapshot),
            payments: payments.map(\.cloudSnapshot)
        )
    }
}

private struct CircleRow: Encodable {
    let id: UUID
    let ownerUserId: UUID?
    let name: String
    let shortCode: String
    let defaultBuyIn: String
    let currencyCode: String
    let memberCount: Int
    let gameCount: Int
    let createdAt: Date
    let lastPlayedAt: Date?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserId = "owner_user_id"
        case name
        case shortCode = "short_code"
        case defaultBuyIn = "default_buy_in"
        case currencyCode = "currency_code"
        case memberCount = "member_count"
        case gameCount = "game_count"
        case createdAt = "created_at"
        case lastPlayedAt = "last_played_at"
        case updatedAt = "updated_at"
    }
}

private struct CircleSummaryUpdate: Encodable {
    let memberCount: Int
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case memberCount = "member_count"
        case updatedAt = "updated_at"
    }
}

private struct CircleActivityUpdate: Encodable {
    let gameCount: Int
    let lastPlayedAt: Date?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case gameCount = "game_count"
        case lastPlayedAt = "last_played_at"
        case updatedAt = "updated_at"
    }
}

private struct CircleMemberRow: Encodable {
    let id: UUID
    let circleId: UUID
    let userId: UUID?
    let displayName: String
    let initial: String
    let handle: String?
    let isCurrentUser: Bool
    let joinedAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case userId = "user_id"
        case displayName = "display_name"
        case initial
        case handle
        case isCurrentUser = "is_current_user"
        case joinedAt = "joined_at"
        case updatedAt = "updated_at"
    }
}

private struct SessionRow: Encodable {
    let id: UUID
    let circleId: UUID
    let title: String
    let status: String
    let buyInAmount: String
    let currencyCode: String
    let potTotal: String
    let startedAt: Date?
    let endedAt: Date?
    let summaryLine: String?
    let players: [SessionPlayerPayload]
    let payments: [SettlementPaymentPayload]
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case title
        case status
        case buyInAmount = "buy_in_amount"
        case currencyCode = "currency_code"
        case potTotal = "pot_total"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case summaryLine = "summary_line"
        case players
        case payments
        case updatedAt = "updated_at"
    }
}

private struct ProfileRow: Codable {
    let id: UUID
    let handle: String
    let handleLower: String
    let displayName: String
    let displayNameLower: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case handleLower = "handle_lower"
        case displayName = "display_name"
        case displayNameLower = "display_name_lower"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID,
        handle: String,
        handleLower: String,
        displayName: String,
        displayNameLower: String,
        updatedAt: Date
    ) {
        self.id = id
        self.handle = handle
        self.handleLower = handleLower
        self.displayName = displayName
        self.displayNameLower = displayNameLower
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        handle = try container.decode(String.self, forKey: .handle)
        handleLower = try container.decode(String.self, forKey: .handleLower)
        displayName = try container.decode(String.self, forKey: .displayName)
        let normalizedLower = displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        displayNameLower = try container.decodeIfPresent(String.self, forKey: .displayNameLower) ?? normalizedLower
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }

    var resolvedDisplayNameLower: String {
        let trimmed = displayNameLower.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct ProfileUpsertRow: Encodable {
    let id: UUID
    let handle: String
    let handleLower: String
    let displayName: String
    let displayNameLower: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case handleLower = "handle_lower"
        case displayName = "display_name"
        case displayNameLower = "display_name_lower"
        case updatedAt = "updated_at"
    }

    var legacyFallback: ProfileLegacyUpsertRow {
        ProfileLegacyUpsertRow(
            id: id,
            handle: handle,
            handleLower: handleLower,
            displayName: displayName,
            updatedAt: updatedAt
        )
    }
}

private struct ProfileLegacyUpsertRow: Encodable {
    let id: UUID
    let handle: String
    let handleLower: String
    let displayName: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case handleLower = "handle_lower"
        case displayName = "display_name"
        case updatedAt = "updated_at"
    }
}

private struct FriendRequestRow: Codable {
    let id: UUID
    let fromUserId: UUID
    let fromHandle: String
    let fromDisplayName: String
    let toUserId: UUID
    let toHandle: String
    let status: String
    let createdAt: Date
    let respondedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case fromUserId = "from_user_id"
        case fromHandle = "from_handle"
        case fromDisplayName = "from_display_name"
        case toUserId = "to_user_id"
        case toHandle = "to_handle"
        case status
        case createdAt = "created_at"
        case respondedAt = "responded_at"
    }
}

private struct FriendRequestResponseUpdate: Encodable {
    let status: String
    let respondedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case respondedAt = "responded_at"
    }
}

private struct CircleWithMembersRow: Decodable {
    let id: UUID
    let name: String
    let shortCode: String
    let defaultBuyIn: String
    let currencyCode: String
    let memberCount: Int
    let gameCount: Int
    let createdAt: Date
    let lastPlayedAt: Date?
    let circleMembers: [CircleMemberPayload]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case shortCode = "short_code"
        case defaultBuyIn = "default_buy_in"
        case currencyCode = "currency_code"
        case memberCount = "member_count"
        case gameCount = "game_count"
        case createdAt = "created_at"
        case lastPlayedAt = "last_played_at"
        case circleMembers = "circle_members"
    }

    var snapshot: CloudCircleSnapshot {
        CloudCircleSnapshot(
            id: id,
            name: name,
            shortCode: shortCode,
            defaultBuyIn: Decimal(string: defaultBuyIn) ?? 20,
            currencyCode: currencyCode,
            memberCount: memberCount,
            gameCount: gameCount,
            createdAt: createdAt,
            lastPlayedAt: lastPlayedAt,
            members: (circleMembers ?? []).map { $0.snapshot(currentUserId: nil) }
        )
    }

    func pullSnapshot(currentUserId: UUID, isOwner: Bool, sessions: [SessionPayloadRow]) -> CloudCirclePullSnapshot {
        CloudCirclePullSnapshot(
            id: id,
            name: name,
            shortCode: shortCode,
            defaultBuyIn: Decimal(string: defaultBuyIn) ?? 20,
            currencyCode: currencyCode,
            memberCount: memberCount,
            gameCount: gameCount,
            createdAt: createdAt,
            lastPlayedAt: lastPlayedAt,
            isOwner: isOwner,
            members: (circleMembers ?? []).map { $0.snapshot(currentUserId: currentUserId) },
            sessions: sessions.map(\.snapshot)
        )
    }
}

private struct CircleMemberPayload: Decodable {
    let id: UUID
    let userId: UUID?
    let displayName: String
    let initial: String
    let handle: String?
    let joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case displayName = "display_name"
        case initial
        case handle
        case joinedAt = "joined_at"
    }

    func snapshot(currentUserId: UUID?) -> CloudMemberSnapshot {
        CloudMemberSnapshot(
            id: id,
            displayName: displayName,
            initial: initial,
            handle: handle,
            userId: userId,
            isCurrentUser: userId == currentUserId,
            joinedAt: joinedAt
        )
    }
}

private struct SessionPlayerPayload: Codable {
    let id: String
    let displayName: String
    let initial: String
    let buyInCount: Int
    let totalIn: String
    let finalOut: String?
    let net: String?
    let memberId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case initial
        case buyInCount = "buy_in_count"
        case totalIn = "total_in"
        case finalOut = "final_out"
        case net
        case memberId = "member_id"
    }
}

private struct SettlementPaymentPayload: Codable {
    let id: String
    let fromInitial: String
    let fromName: String
    let toInitial: String
    let toName: String
    let amount: String

    enum CodingKeys: String, CodingKey {
        case id
        case fromInitial = "from_initial"
        case fromName = "from_name"
        case toInitial = "to_initial"
        case toName = "to_name"
        case amount
    }
}

private extension SessionPlayerPayload {
    var cloudSnapshot: CloudSessionPlayerSnapshot {
        CloudSessionPlayerSnapshot(
            id: UUID(uuidString: id) ?? UUID(),
            displayName: displayName,
            initial: initial,
            buyInCount: buyInCount,
            totalIn: Decimal(string: totalIn) ?? 0,
            finalOut: finalOut.flatMap { Decimal(string: $0) },
            net: net.flatMap { Decimal(string: $0) },
            memberId: memberId.flatMap(UUID.init(uuidString:))
        )
    }
}

private extension SettlementPaymentPayload {
    var cloudSnapshot: CloudSettlementPaymentSnapshot {
        CloudSettlementPaymentSnapshot(
            id: UUID(uuidString: id) ?? UUID(),
            fromInitial: fromInitial,
            fromName: fromName,
            toInitial: toInitial,
            toName: toName,
            amount: Decimal(string: amount) ?? 0
        )
    }
}

private extension SessionPlayerModel {
    var cloudPayload: SessionPlayerPayload {
        SessionPlayerPayload(
            id: id.uuidString,
            displayName: displayName,
            initial: initial,
            buyInCount: buyInCount,
            totalIn: totalIn.cloudString,
            finalOut: finalOut?.cloudString,
            net: net?.cloudString,
            memberId: memberId?.uuidString
        )
    }
}

private extension SettlementPaymentModel {
    var cloudPayload: SettlementPaymentPayload {
        SettlementPaymentPayload(
            id: id.uuidString,
            fromInitial: fromInitial,
            fromName: fromName,
            toInitial: toInitial,
            toName: toName,
            amount: amount.cloudString
        )
    }
}

private extension Decimal {
    var cloudString: String {
        NSDecimalNumber(decimal: self).stringValue
    }
}
