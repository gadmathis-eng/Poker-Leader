import Foundation
import SwiftData

enum CircleRepositoryError: LocalizedError {
    case duplicateInviteCode
    case duplicateMemberName(String)

    var errorDescription: String? {
        switch self {
        case .duplicateInviteCode:
            return "Could not create a unique invite code. Please try again."
        case .duplicateMemberName(let name):
            return "\(name) is already in this circle. Use your real name once, and add a nickname instead."
        }
    }
}

@MainActor
final class CircleRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() throws -> [CircleModel] {
        let descriptor = FetchDescriptor<CircleModel>(sortBy: [SortDescriptor(\.name)])
        return try context.fetch(descriptor)
    }

    func delete(_ circle: CircleModel) {
        let circleId = circle.id
        let isOwner = CircleCreatorStore.isCreator(of: circleId)

        DeletedCirclesStore.markDeleted(circleId)
        CircleCreatorStore.unmarkCreator(circleId)
        context.delete(circle)
        try? context.save()

        Task {
            if isOwner {
                try? await SupabaseSyncService.shared.deleteCircle(id: circleId)
            } else {
                try? await SupabaseSyncService.shared.leaveCircle(circleId: circleId)
            }
        }
    }

    func fetch(id: UUID) throws -> CircleModel? {
        let descriptor = FetchDescriptor<CircleModel>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    func create(
        name: String,
        shortCode: String,
        defaultBuyIn: Decimal = 20,
        currencyCode: String = "GBP",
        syncToCloud: Bool = true
    ) -> CircleModel {
        let circle = CircleModel(
            name: name,
            shortCode: shortCode.uppercased(),
            defaultBuyIn: defaultBuyIn.clampedToNonNegative,
            currencyCode: currencyCode
        )
        context.insert(circle)
        try? context.save()
        if syncToCloud {
            Task {
                try? await SupabaseSyncService.shared.upsertCircle(circle)
            }
        }
        return circle
    }

    func createSynced(
        name: String,
        currentUserDisplayName: String,
        currentUserHandle: String?,
        currencyCode: String = CurrencyPreferences.defaultCurrencyCode
    ) async throws -> CircleModel {
        let shortCode = try await makeUniqueInviteCode()
        let circle = create(name: name, shortCode: shortCode, currencyCode: currencyCode, syncToCloud: false)
        let member = try addMember(
            to: circle,
            displayName: currentUserDisplayName,
            initial: Self.initial(for: currentUserDisplayName),
            handle: currentUserHandle,
            isCurrentUser: true,
            syncToCloud: false
        )

        try await SupabaseSyncService.shared.upsertCircle(circle)
        try await SupabaseSyncService.shared.upsertMember(member, in: circle)
        return circle
    }

    func addMember(
        to circle: CircleModel,
        displayName: String,
        initial: String,
        handle: String? = nil,
        isCurrentUser: Bool = false,
        syncToCloud: Bool = true
    ) throws -> MemberModel {
        let cleanedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasMemberName(cleanedDisplayName, in: circle) {
            throw CircleRepositoryError.duplicateMemberName(cleanedDisplayName)
        }

        let member = MemberModel(
            displayName: cleanedDisplayName,
            initial: initial.uppercased(),
            handle: Self.normalizedHandle(handle),
            isCurrentUser: isCurrentUser
        )
        member.circle = circle
        circle.members.append(member)
        circle.memberCount = circle.members.count
        context.insert(member)
        try? context.save()
        if syncToCloud {
            Task {
                try? await SupabaseSyncService.shared.upsertMember(member, in: circle)
            }
        }
        return member
    }

    func joinWithInviteCode(_ code: String, for member: MemberModel) throws -> CircleModel? {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let descriptor = FetchDescriptor<CircleModel>(predicate: #Predicate { $0.shortCode == normalized })
        guard let circle = try context.fetch(descriptor).first else { return nil }
        if hasMemberName(member.displayName, in: circle) {
            throw CircleRepositoryError.duplicateMemberName(member.displayName)
        }
        member.circle = circle
        circle.members.append(member)
        circle.memberCount = circle.members.count
        try context.save()
        Task {
            try? await SupabaseSyncService.shared.upsertMember(member, in: circle)
        }
        return circle
    }

    func joinWithInviteCode(_ code: String, displayName: String, initial: String, handle: String?) async throws -> CircleModel? {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let circle = try fetchLocalCircle(inviteCode: normalized) {
            let member = try addMember(
                to: circle,
                displayName: displayName,
                initial: initial,
                handle: handle,
                isCurrentUser: true,
                syncToCloud: false
            )
            try await SupabaseSyncService.shared.upsertMember(member, in: circle)
            return circle
        }

        guard let snapshot = try await SupabaseSyncService.shared.fetchCircle(inviteCode: normalized) else {
            return nil
        }

        let circle = upsertLocalCircle(from: snapshot)
        let member = try addMember(
            to: circle,
            displayName: displayName,
            initial: initial,
            handle: handle,
            isCurrentUser: true,
            syncToCloud: false
        )
        try await SupabaseSyncService.shared.upsertMember(member, in: circle)
        return circle
    }

    func syncFromCloud(displayName: String, playerHandle: String) async throws {
        let snapshots = try await SupabaseSyncService.shared.fetchCirclesForCurrentUser()
        let deletedIds = DeletedCirclesStore.deletedIds
        let cloudIds = Set(snapshots.map(\.id))

        for deletedId in deletedIds where !cloudIds.contains(deletedId) {
            DeletedCirclesStore.unmarkDeleted(deletedId)
        }

        for snapshot in snapshots where !deletedIds.contains(snapshot.id) {
            upsertLocalCircle(
                from: snapshot,
                fallbackDisplayName: displayName,
                fallbackHandle: playerHandle
            )
        }

        for deletedId in DeletedCirclesStore.deletedIds {
            if let circle = try? fetch(id: deletedId) {
                context.delete(circle)
            }
        }

        try context.save()
    }

    private func fetchLocalCircle(inviteCode: String) throws -> CircleModel? {
        let descriptor = FetchDescriptor<CircleModel>(predicate: #Predicate { $0.shortCode == inviteCode })
        return try context.fetch(descriptor).first
    }

    private func upsertLocalCircle(from snapshot: CloudCircleSnapshot) -> CircleModel {
        upsertLocalCircle(
            from: CloudCirclePullSnapshot(
                id: snapshot.id,
                name: snapshot.name,
                shortCode: snapshot.shortCode,
                defaultBuyIn: snapshot.defaultBuyIn,
                currencyCode: snapshot.currencyCode,
                memberCount: snapshot.memberCount,
                gameCount: snapshot.gameCount,
                createdAt: snapshot.createdAt,
                lastPlayedAt: snapshot.lastPlayedAt,
                isOwner: false,
                members: snapshot.members,
                sessions: []
            ),
            fallbackDisplayName: "Your name",
            fallbackHandle: nil
        )
    }

    private func upsertLocalCircle(
        from snapshot: CloudCirclePullSnapshot,
        fallbackDisplayName: String,
        fallbackHandle: String?
    ) -> CircleModel {
        let snapshotId = snapshot.id
        let descriptor = FetchDescriptor<CircleModel>(predicate: #Predicate { $0.id == snapshotId })
        let circle = (try? context.fetch(descriptor).first) ?? CircleModel(
            id: snapshot.id,
            name: snapshot.name,
            shortCode: snapshot.shortCode,
            defaultBuyIn: snapshot.defaultBuyIn,
            currencyCode: snapshot.currencyCode,
            memberCount: snapshot.memberCount,
            gameCount: snapshot.gameCount,
            createdAt: snapshot.createdAt,
            lastPlayedAt: snapshot.lastPlayedAt
        )

        if circle.modelContext == nil {
            context.insert(circle)
        }

        circle.name = snapshot.name
        circle.shortCode = snapshot.shortCode
        circle.defaultBuyIn = snapshot.defaultBuyIn
        circle.currencyCode = snapshot.currencyCode
        circle.memberCount = snapshot.memberCount
        circle.gameCount = snapshot.gameCount
        circle.lastPlayedAt = snapshot.lastPlayedAt

        for existingMember in circle.members {
            existingMember.isCurrentUser = false
        }

        for remoteMember in snapshot.members {
            if let member = circle.members.first(where: { $0.id == remoteMember.id }) {
                member.displayName = remoteMember.displayName
                member.initial = remoteMember.initial
                member.handle = remoteMember.handle
                member.isCurrentUser = remoteMember.isCurrentUser
                member.joinedAt = remoteMember.joinedAt
                continue
            }

            let member = MemberModel(
                id: remoteMember.id,
                displayName: remoteMember.displayName,
                initial: remoteMember.initial,
                handle: remoteMember.handle,
                isCurrentUser: remoteMember.isCurrentUser,
                joinedAt: remoteMember.joinedAt
            )
            member.circle = circle
            circle.members.append(member)
            context.insert(member)
        }

        if !circle.members.contains(where: \.isCurrentUser) {
            let cleanedName = fallbackDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let member = MemberModel(
                displayName: cleanedName,
                initial: Self.initial(for: cleanedName),
                handle: Self.normalizedHandle(fallbackHandle),
                isCurrentUser: true
            )
            member.circle = circle
            circle.members.append(member)
            context.insert(member)
        }

        circle.memberCount = max(circle.memberCount, circle.members.count)

        for remoteSession in snapshot.sessions {
            upsertLocalSession(remoteSession, in: circle)
        }

        if snapshot.isOwner {
            CircleCreatorStore.markCreator(circle.id)
        }

        try? context.save()
        return circle
    }

    private func upsertLocalSession(_ snapshot: CloudSessionSnapshot, in circle: CircleModel) {
        let sessionId = snapshot.id
        let descriptor = FetchDescriptor<SessionModel>(predicate: #Predicate { $0.id == sessionId })
        let session = (try? context.fetch(descriptor).first) ?? SessionModel(
            id: snapshot.id,
            title: snapshot.title,
            status: SessionStatus(rawValue: snapshot.status) ?? .settled,
            buyInAmount: snapshot.buyInAmount,
            currencyCode: snapshot.currencyCode,
            potTotal: snapshot.potTotal,
            startedAt: snapshot.startedAt ?? .now,
            endedAt: snapshot.endedAt,
            summaryLine: snapshot.summaryLine
        )

        if session.modelContext == nil {
            context.insert(session)
            session.circle = circle
            circle.sessions.append(session)
        }

        session.title = snapshot.title
        session.status = SessionStatus(rawValue: snapshot.status) ?? session.status
        session.buyInAmount = snapshot.buyInAmount
        session.currencyCode = snapshot.currencyCode
        session.potTotal = snapshot.potTotal
        session.startedAt = snapshot.startedAt ?? session.startedAt
        session.endedAt = snapshot.endedAt
        session.summaryLine = snapshot.summaryLine

        for playerSnapshot in snapshot.players {
            if let player = session.players.first(where: { $0.id == playerSnapshot.id }) {
                player.displayName = playerSnapshot.displayName
                player.initial = playerSnapshot.initial
                player.buyInCount = playerSnapshot.buyInCount
                player.totalIn = playerSnapshot.totalIn
                player.finalOut = playerSnapshot.finalOut
                player.net = playerSnapshot.net
                player.memberId = playerSnapshot.memberId
                continue
            }

            let player = SessionPlayerModel(
                id: playerSnapshot.id,
                displayName: playerSnapshot.displayName,
                initial: playerSnapshot.initial,
                buyInCount: playerSnapshot.buyInCount,
                totalIn: playerSnapshot.totalIn,
                finalOut: playerSnapshot.finalOut,
                net: playerSnapshot.net,
                memberId: playerSnapshot.memberId
            )
            player.session = session
            session.players.append(player)
            context.insert(player)
        }

        session.payments.removeAll()
        for paymentSnapshot in snapshot.payments {
            let payment = SettlementPaymentModel(
                id: paymentSnapshot.id,
                fromInitial: paymentSnapshot.fromInitial,
                fromName: paymentSnapshot.fromName,
                toInitial: paymentSnapshot.toInitial,
                toName: paymentSnapshot.toName,
                amount: paymentSnapshot.amount
            )
            payment.session = session
            session.payments.append(payment)
            context.insert(payment)
        }
    }


    static func initial(for displayName: String) -> String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "Y"
    }

    static func normalizedHandle(_ handle: String?) -> String? {
        guard var cleaned = handle?.trimmingCharacters(in: .whitespacesAndNewlines), !cleaned.isEmpty else {
            return nil
        }
        if !cleaned.hasPrefix("@") {
            cleaned = "@\(cleaned)"
        }
        return cleaned
    }

    private func hasMemberName(_ displayName: String, in circle: CircleModel, excluding memberId: UUID? = nil) -> Bool {
        let normalized = normalizedName(displayName)
        return circle.members.contains { member in
            member.id != memberId && normalizedName(member.displayName) == normalized
        }
    }

    private func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func makeUniqueInviteCode() async throws -> String {
        for _ in 0..<20 {
            let code = Self.randomInviteCode()
            if try fetchLocalCircle(inviteCode: code) == nil,
               try await SupabaseSyncService.shared.fetchCircle(inviteCode: code) == nil {
                return code
            }
        }
        throw CircleRepositoryError.duplicateInviteCode
    }

    private static func randomInviteCode(length: Int = 6) -> String {
        let characters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }
}
