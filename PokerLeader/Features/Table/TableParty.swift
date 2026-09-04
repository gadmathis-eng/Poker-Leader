import Foundation
import Observation

struct TablePartyPlayer: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var seat: Int
    var stack: Decimal
    var isYou: Bool

    init(
        id: UUID = UUID(),
        name: String,
        seat: Int,
        stack: Decimal,
        isYou: Bool = false
    ) {
        self.id = id
        self.name = name
        self.seat = seat
        self.stack = stack
        self.isYou = isYou
    }
}

/// A table lobby whose `players` array is always kept in join order, so the
/// element at index 0 is the creator and index 1 is the second player to join.
@Observable
final class TableParty {
    private(set) var players: [TablePartyPlayer] = []
    private(set) var leaderId: UUID?
    private(set) var isStarted = false

    static let minimumPlayersToStart = 2

    private let defaults: UserDefaults
    private let storageKey = "tablePartyState"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    var leader: TablePartyPlayer? {
        players.first { $0.id == leaderId }
    }

    var you: TablePartyPlayer? {
        players.first(where: \.isYou)
    }

    var canStart: Bool {
        !isStarted && players.count >= Self.minimumPlayersToStart
    }

    func isLeader(_ playerId: UUID) -> Bool {
        leaderId == playerId
    }

    var youAreLeader: Bool {
        guard let you else { return false }
        return isLeader(you.id)
    }

    func player(inSeat seat: Int) -> TablePartyPlayer? {
        players.first { $0.seat == seat }
    }

    /// Adds a player to the table. The first player to join creates the game
    /// and becomes the leader.
    @discardableResult
    func join(name: String, seat: Int, stack: Decimal, isYou: Bool = false) -> TablePartyPlayer? {
        guard seat > 0, player(inSeat: seat) == nil else { return nil }
        if isYou, you != nil { return nil }

        let player = TablePartyPlayer(name: name, seat: seat, stack: stack, isYou: isYou)
        players.append(player)

        if leaderId == nil {
            leaderId = player.id
        }

        save()
        return player
    }

    /// Removes a player. When the leader leaves, leadership passes to the
    /// longest-standing remaining player — the second person who joined.
    func leave(_ playerId: UUID) {
        guard let index = players.firstIndex(where: { $0.id == playerId }) else { return }

        players.remove(at: index)

        if leaderId == playerId {
            leaderId = players.first?.id
        }

        if players.isEmpty {
            isStarted = false
        }

        save()
    }

    /// Tops a player up by `amount`. Negative amounts are ignored so a stack
    /// can never be reduced through the add control.
    func addToStack(_ amount: Decimal, for playerId: UUID) {
        guard amount > 0 else { return }
        guard let index = players.firstIndex(where: { $0.id == playerId }) else { return }

        players[index].stack += amount
        save()
    }

    func startGame() {
        guard canStart else { return }
        isStarted = true
        save()
    }

    func reset() {
        players = []
        leaderId = nil
        isStarted = false
        save()
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var players: [TablePartyPlayer]
        var leaderId: UUID?
        var isStarted: Bool
    }

    private func save() {
        let snapshot = Snapshot(players: players, leaderId: leaderId, isStarted: isStarted)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func load() {
        guard
            let data = defaults.data(forKey: storageKey),
            let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }

        players = snapshot.players
        leaderId = snapshot.leaderId
        isStarted = snapshot.isStarted

        if leaderId == nil || !players.contains(where: { $0.id == leaderId }) {
            leaderId = players.first?.id
        }
    }
}
