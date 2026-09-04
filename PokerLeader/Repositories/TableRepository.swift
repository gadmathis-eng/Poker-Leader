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
        return error
    }

    static func isMissingOpenTablesSchema(_ error: Error) -> Bool {
        let text = [
            error.localizedDescription,
            String(describing: error),
            (error as? LocalizedError)?.errorDescription,
            (error as? LocalizedError)?.failureReason
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        let mentionsTable = text.contains("open_tables")
        let looksMissing = text.contains("schema cache")
            || text.contains("could not find the table")
            || text.contains("does not exist")
        return mentionsTable && looksMissing
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

    func updateAnte(_ amount: Decimal, on table: OpenTableModel) {
        table.anteAmount = TableMoney.string(amount)
        table.updatedAt = .now
        try? context.save()
        publish(table)
    }

    /// Deals the pre-flop round so the table gets asked, seat by seat, who is in.
    @discardableResult
    func dealHand(on table: OpenTableModel) throws -> SharedTableHand {
        let hand = try PreflopRound.start(
            seats: table.seats,
            dealerSeat: PreflopRound.openingDealerSeat(seats: table.seats),
            ante: table.anteDecimal
        )
        table.isStarted = true
        table.hand = hand
        try context.save()
        publish(table)
        return hand
    }

    func updateHand(_ hand: SharedTableHand, on table: OpenTableModel) {
        table.hand = hand
        try? context.save()
        publish(table)
    }

    /// Pushes the pot to the winner and deals the next pre-flop round.
    func settleHandAndDealNext(on table: OpenTableModel) throws {
        guard let hand = table.hand else { throw PreflopRoundError.bettingOpen }
        guard hand.winnerSeat != nil else { throw PreflopRoundError.bettingOpen }

        let stacks = PreflopRound.stacksAfter(hand)
        var seats = table.seats
        for index in seats.indices {
            guard let stack = stacks[seats[index].playerKey] else { continue }
            seats[index].amount = TableMoney.string(stack)
        }
        table.seats = seats

        table.hand = try? PreflopRound.start(
            seats: seats,
            dealerSeat: PreflopRound.nextDealerSeat(after: hand.dealerSeat, seats: seats),
            ante: table.anteDecimal,
            handNumber: hand.handNumber + 1
        )
        try context.save()
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

        do {
            if table.isHostLocally {
                try await SupabaseSyncService.shared.upsertOpenTable(table)
            } else {
                try await SupabaseSyncService.shared.updateOpenTableSeats(table)
            }
        } catch {
            throw TableRepositoryError.wrapping(error)
        }
    }

    private func leave(_ table: OpenTableModel) async {
        if mySeat(on: table) != nil {
            await refresh(table: table)
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
            anteAmount: snapshot.anteAmount,
            hand: snapshot.hand,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt
        )
        context.insert(table)
        try? context.save()
        return table
    }

    private func apply(snapshot: CloudOpenTableSnapshot, existing table: OpenTableModel) {
        let localHand = table.hand
        let localUpdatedAt = table.updatedAt
        table.hostDisplayName = snapshot.hostDisplayName
        table.hostPlayerKey = snapshot.hostPlayerKey
        table.sessionCurrencyCode = snapshot.sessionCurrencyCode
        table.isStarted = snapshot.isStarted
        table.seats = snapshot.seats
        table.anteAmount = snapshot.anteAmount
        table.hand = mergedHand(
            local: localHand,
            cloud: snapshot.hand,
            cloudUpdatedAt: snapshot.updatedAt,
            localUpdatedAt: localUpdatedAt
        )
        table.updatedAt = snapshot.updatedAt
        try? context.save()
    }

    /// A move made on this device stays put until the cloud catches up with it.
    private func mergedHand(
        local: SharedTableHand?,
        cloud: SharedTableHand?,
        cloudUpdatedAt: Date,
        localUpdatedAt: Date
    ) -> SharedTableHand? {
        guard let local else { return cloud }
        guard let cloud else {
            return cloudUpdatedAt > localUpdatedAt ? nil : local
        }
        if local.id == cloud.id, local.revision > cloud.revision {
            return local
        }
        return cloud
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
