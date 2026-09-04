import Foundation
import SwiftData

enum TableRepositoryError: LocalizedError, Equatable {
    case tableNotFound
    case notSignedIn
    case cloudUnavailable
    case schemaMissing

    var errorDescription: String? {
        switch self {
        case .tableNotFound:
            "No table found for that code. Ask the host to share it again."
        case .notSignedIn:
            "Sign in to join a shared table."
        case .cloudUnavailable:
            "Cloud sync is needed so other people can join this table."
        case .schemaMissing:
            "Shared tables aren't set up yet. In Supabase, open SQL Editor and run supabase/migrations/20260904120000_open_tables.sql, then try again."
        }
    }

    static func wrapping(_ error: Error) -> Error {
        if isMissingOpenTablesSchema(error) {
            return schemaMissing
        }
        if let seating = SharedTableSeatingError.matching(error) {
            return seating
        }
        return error
    }

    static func isMissingOpenTablesSchema(_ error: Error) -> Bool {
        let text = errorSearchText(error)
        let mentionsShared = text.contains("open_tables") || text.contains("merge_open_table_seat")
        let looksMissing = text.contains("schema cache")
            || text.contains("could not find the table")
            || text.contains("could not find the function")
            || text.contains("does not exist")
            || text.contains("pgrst202")
            || text.contains("pgrst205")
        return mentionsShared && looksMissing
    }

    static func errorSearchText(_ error: Error) -> String {
        [
            error.localizedDescription,
            String(describing: error),
            (error as? LocalizedError)?.errorDescription,
            (error as? LocalizedError)?.failureReason
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
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

        do {
            guard let snapshot = try await SupabaseSyncService.shared.fetchOpenTable(inviteCode: normalized) else {
                throw TableRepositoryError.tableNotFound
            }

            let table = apply(snapshot: snapshot, isHostLocally: snapshot.hostPlayerKey == localPlayerKey)
            activeInviteCode = table.inviteCode
            return table
        } catch let error as TableRepositoryError {
            throw error
        } catch {
            throw TableRepositoryError.wrapping(error)
        }
    }

    func occupySeat(
        on table: OpenTableModel,
        seatNumber: Int,
        playerName: String,
        handle: String?,
        amount: Decimal
    ) async throws {
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
        try await publishLocalSeatNow(on: table)
    }

    func updateLocalAmount(on table: OpenTableModel, amount: Decimal) {
        var seats = table.seats
        guard let index = seats.firstIndex(where: { $0.playerKey == localPlayerKey }) else { return }
        seats[index].amount = NSDecimalNumber(decimal: amount.clampedToNonNegative).stringValue
        table.seats = seats
        try? context.save()
        publishLocalSeat(on: table)
    }

    func markStarted(_ table: OpenTableModel) {
        table.isStarted = true
        table.updatedAt = .now
        try? context.save()

        guard SupabaseBootstrap.isConfigured, SupabaseAuthManager.shared.isSignedIn else { return }
        Task {
            do {
                try await SupabaseSyncService.shared.markOpenTableStarted(inviteCode: table.inviteCode)
            } catch {
                try? await publishForSharing(table)
            }
        }
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
            try? await publishForSharing(table)
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

        do {
            if table.isHostLocally {
                try await SupabaseSyncService.shared.upsertOpenTable(table)
            }
            try await publishLocalSeatNow(on: table)
        } catch {
            throw TableRepositoryError.wrapping(error)
        }
    }

    private func publishLocalSeat(on table: OpenTableModel) {
        table.updatedAt = .now
        try? context.save()

        guard SupabaseBootstrap.isConfigured, SupabaseAuthManager.shared.isSignedIn else { return }
        Task {
            try? await publishLocalSeatNow(on: table)
        }
    }

    private func publishLocalSeatNow(on table: OpenTableModel) async throws {
        guard let seat = table.seats.first(where: { $0.playerKey == localPlayerKey }) else {
            return
        }

        do {
            try await applyMergedSeat(seat, on: table)
        } catch {
            if table.isHostLocally, shouldCreateMissingTable(error) {
                try await SupabaseSyncService.shared.upsertOpenTable(table)
                try await applyMergedSeat(seat, on: table)
                return
            }
            throw TableRepositoryError.wrapping(error)
        }
    }

    private func applyMergedSeat(_ seat: SharedTableSeat, on table: OpenTableModel) async throws {
        table.seats = try await SupabaseSyncService.shared.mergeOpenTableSeat(
            seat,
            inviteCode: table.inviteCode
        )
        try? context.save()
    }

    private func shouldCreateMissingTable(_ error: Error) -> Bool {
        if TableRepositoryError.isMissingOpenTablesSchema(error) {
            return false
        }
        let text = TableRepositoryError.errorSearchText(error)
        return text.contains("table not found") || text.contains("no rows")
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
