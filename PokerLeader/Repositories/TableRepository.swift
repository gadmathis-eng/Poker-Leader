import Foundation
import SwiftData

enum TableRepositoryError: LocalizedError, Equatable {
    case tableNotFound
    case notSignedIn
    case cloudUnavailable

    var errorDescription: String? {
        switch self {
        case .tableNotFound:
            "No table found for that link. Ask the host to share it again."
        case .notSignedIn:
            "Sign in to join a shared table."
        case .cloudUnavailable:
            "Cloud sync is needed so other people can join this table."
        }
    }
}

@MainActor
final class TableRepository {
    private static let activeInviteCodeKey = "activeTableInviteCode"
    private static let playerKeyKey = "tablePlayerKey"

    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    var localPlayerKey: String {
        if let userId = SupabaseAuthManager.shared.userId, !userId.isEmpty {
            return userId
        }

        if let existing = UserDefaults.standard.string(forKey: Self.playerKeyKey), !existing.isEmpty {
            return existing
        }

        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: Self.playerKeyKey)
        return created
    }

    var activeInviteCode: String? {
        get {
            let code = UserDefaults.standard.string(forKey: Self.activeInviteCodeKey) ?? ""
            return code.isEmpty ? nil : TableInviteDeepLink.normalizedCode(code)
        }
        set {
            UserDefaults.standard.set(newValue.map(TableInviteDeepLink.normalizedCode) ?? "", forKey: Self.activeInviteCodeKey)
        }
    }

    func activeTable() throws -> OpenTableModel? {
        guard let code = activeInviteCode else { return nil }
        return try table(inviteCode: code)
    }

    func table(inviteCode: String) throws -> OpenTableModel? {
        let normalized = TableInviteDeepLink.normalizedCode(inviteCode)
        let descriptor = FetchDescriptor<OpenTableModel>(predicate: #Predicate { $0.inviteCode == normalized })
        return try context.fetch(descriptor).first
    }

    func makeActive(_ table: OpenTableModel) {
        activeInviteCode = table.inviteCode
    }

    func mySeat(on table: OpenTableModel) -> SharedTableSeat? {
        table.seat(forPlayerKey: localPlayerKey)
    }

    func ensureHostTable(
        sessionCurrencyCode: String,
        hostDisplayName: String
    ) throws -> OpenTableModel {
        if let existing = try activeTable() {
            existing.sessionCurrencyCode = sessionCurrencyCode
            existing.hostDisplayName = hostDisplayName
            if existing.isHostLocally {
                existing.hostPlayerKey = localPlayerKey
            }
            existing.updatedAt = .now
            try context.save()
            return existing
        }

        let table = OpenTableModel(
            inviteCode: try uniqueInviteCode(),
            hostDisplayName: hostDisplayName,
            hostPlayerKey: localPlayerKey,
            sessionCurrencyCode: sessionCurrencyCode,
            isHostLocally: true
        )
        context.insert(table)
        activeInviteCode = table.inviteCode
        try context.save()
        return table
    }

    func join(inviteCode: String, displayName: String) async throws -> OpenTableModel {
        let normalized = TableInviteDeepLink.normalizedCode(inviteCode)
        guard !normalized.isEmpty else {
            throw TableRepositoryError.tableNotFound
        }

        if let local = try table(inviteCode: normalized) {
            activeInviteCode = local.inviteCode
            await refresh(table: local)
            return local
        }

        guard SupabaseBootstrap.isConfigured else {
            throw TableRepositoryError.cloudUnavailable
        }
        guard SupabaseAuthManager.shared.isSignedIn else {
            throw TableRepositoryError.notSignedIn
        }

        guard let snapshot = try await SupabaseSyncService.shared.fetchOpenTable(inviteCode: normalized) else {
            throw TableRepositoryError.tableNotFound
        }

        let table = apply(snapshot: snapshot, isHostLocally: snapshot.hostPlayerKey == localPlayerKey)
        activeInviteCode = table.inviteCode
        return table
    }

    func occupySeat(
        on table: OpenTableModel,
        seatNumber: Int,
        playerName: String,
        handle: String?,
        amount: Decimal
    ) throws {
        table.seats = try SharedTableSeating.occupy(
            seats: table.seats,
            seatNumber: seatNumber,
            playerKey: localPlayerKey,
            playerName: playerName,
            handle: handle,
            amount: amount,
            isHost: table.hostPlayerKey == localPlayerKey
        )
        try context.save()
        publish(table)
    }

    func rename(_ table: OpenTableModel, to name: String) {
        table.name = TableNaming.normalized(name)
        try? context.save()
    }

    func updateSessionCurrency(on table: OpenTableModel, to currencyCode: String) {
        guard table.isHostLocally else { return }
        let normalized = CurrencyPreferences.normalizedCurrencyCode(currencyCode)
        guard normalized != table.sessionCurrencyCode else { return }

        table.sessionCurrencyCode = normalized
        table.updatedAt = .now
        try? context.save()
        publish(table)
    }

    func remove(_ table: OpenTableModel) async {
        if table.isHostLocally {
            await deleteHosted(table)
        } else {
            await leave(table)
        }
    }

    func updateLocalAmount(on table: OpenTableModel, amount: Decimal) {
        var seats = table.seats
        guard let index = seats.firstIndex(where: { $0.playerKey == localPlayerKey }) else { return }
        seats[index].amount = NSDecimalNumber(decimal: amount.clampedToNonNegative).stringValue
        table.seats = seats
        try? context.save()
        publish(table)
    }

    func markStarted(_ table: OpenTableModel) {
        table.isStarted = true
        table.updatedAt = .now
        try? context.save()
        publish(table)
    }

    func refresh(table: OpenTableModel) async {
        guard SupabaseBootstrap.isConfigured, SupabaseAuthManager.shared.isSignedIn else { return }
        guard let snapshot = try? await SupabaseSyncService.shared.fetchOpenTable(inviteCode: table.inviteCode) else {
            return
        }
        apply(snapshot: snapshot, existing: table)
    }

    func publish(_ table: OpenTableModel) {
        table.updatedAt = .now
        try? context.save()

        guard SupabaseBootstrap.isConfigured, SupabaseAuthManager.shared.isSignedIn else { return }
        Task {
            if table.isHostLocally {
                try? await SupabaseSyncService.shared.upsertOpenTable(table)
            } else {
                try? await SupabaseSyncService.shared.updateOpenTableSeats(table)
            }
        }
    }

    func publishForSharing(_ table: OpenTableModel) async throws {
        guard SupabaseBootstrap.isConfigured else {
            throw TableRepositoryError.cloudUnavailable
        }
        guard SupabaseAuthManager.shared.isSignedIn else {
            throw TableRepositoryError.notSignedIn
        }

        table.updatedAt = .now
        try context.save()

        if table.isHostLocally {
            try await SupabaseSyncService.shared.upsertOpenTable(table)
        } else {
            try await SupabaseSyncService.shared.updateOpenTableSeats(table)
        }
    }

    private func leave(_ table: OpenTableModel) async {
        if mySeat(on: table) != nil {
            table.seats = SharedTableSeating.removing(playerKey: localPlayerKey, from: table.seats)
            try? context.save()
            if SupabaseBootstrap.isConfigured, SupabaseAuthManager.shared.isSignedIn {
                try? await SupabaseSyncService.shared.updateOpenTableSeats(table)
            }
        }
        forget(table)
    }

    private func deleteHosted(_ table: OpenTableModel) async {
        if SupabaseBootstrap.isConfigured, SupabaseAuthManager.shared.isSignedIn {
            try? await SupabaseSyncService.shared.deleteOpenTable(inviteCode: table.inviteCode)
        }
        forget(table)
    }

    private func forget(_ table: OpenTableModel) {
        if activeInviteCode == table.inviteCode {
            activeInviteCode = nil
        }
        context.delete(table)
        try? context.save()
    }

    @discardableResult
    private func apply(snapshot: CloudOpenTableSnapshot, isHostLocally: Bool) -> OpenTableModel {
        if let existing = try? table(inviteCode: snapshot.inviteCode) {
            apply(snapshot: snapshot, existing: existing)
            existing.isHostLocally = isHostLocally || existing.isHostLocally
            return existing
        }

        let table = OpenTableModel(
            id: snapshot.id,
            inviteCode: snapshot.inviteCode,
            hostDisplayName: snapshot.hostDisplayName,
            hostPlayerKey: snapshot.hostPlayerKey,
            sessionCurrencyCode: snapshot.sessionCurrencyCode,
            isStarted: snapshot.isStarted,
            isHostLocally: isHostLocally,
            seats: snapshot.seats,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt
        )
        context.insert(table)
        try? context.save()
        return table
    }

    private func apply(snapshot: CloudOpenTableSnapshot, existing table: OpenTableModel) {
        table.hostDisplayName = snapshot.hostDisplayName
        table.hostPlayerKey = snapshot.hostPlayerKey
        table.sessionCurrencyCode = snapshot.sessionCurrencyCode
        table.isStarted = snapshot.isStarted
        table.seats = snapshot.seats
        table.updatedAt = snapshot.updatedAt
        try? context.save()
    }

    private func uniqueInviteCode() throws -> String {
        for _ in 0..<20 {
            let code = Self.randomInviteCode()
            if try table(inviteCode: code) == nil {
                return code
            }
        }
        return Self.randomInviteCode()
    }

    private static func randomInviteCode(length: Int = 6) -> String {
        let characters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }
}
