import Foundation
import SwiftData

@Model
final class OpenTableModel {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var inviteCode: String
    var name: String?
    var hostDisplayName: String
    var hostPlayerKey: String
    var sessionCurrencyCode: String
    var isStarted: Bool
    var isHostLocally: Bool
    var seatsData: Data
    var anteAmount: String = "0"
    var handData: Data = Data()
    var createdAt: Date
    var updatedAt: Date

    var seats: [SharedTableSeat] {
        get {
            guard !seatsData.isEmpty else { return [] }
            let decoded = (try? JSONDecoder().decode([SharedTableSeat].self, from: seatsData)) ?? []
            return OpenTableSeatsPacking.players(in: decoded)
        }
        set {
            seatsData = (try? JSONEncoder().encode(OpenTableSeatsPacking.players(in: newValue))) ?? Data()
            updatedAt = .now
        }
    }


    var hand: SharedTableHand? {
        get {
            guard !handData.isEmpty else { return nil }
            return try? JSONDecoder().decode(SharedTableHand.self, from: handData)
        }
        set {
            handData = newValue.flatMap { try? JSONEncoder().encode($0) } ?? Data()
            updatedAt = .now
        }
    }

    var anteDecimal: Decimal {
        TableMoney.decimal(anteAmount)
    }

    var displayTitle: String {
        TableNaming.title(name: name, inviteCode: inviteCode)
    }

    func seat(forPlayerKey playerKey: String) -> SharedTableSeat? {
        seats.first { $0.playerKey == playerKey }
    }

    init(
        id: UUID = UUID(),
        inviteCode: String,
        name: String? = nil,
        hostDisplayName: String,
        hostPlayerKey: String,
        sessionCurrencyCode: String,
        isStarted: Bool = false,
        isHostLocally: Bool,
        seats: [SharedTableSeat] = [],
        anteAmount: String = "0",
        hand: SharedTableHand? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.inviteCode = TableInviteDeepLink.normalizedCode(inviteCode)
        self.name = TableNaming.normalized(name)
        self.hostDisplayName = hostDisplayName
        self.hostPlayerKey = hostPlayerKey
        self.sessionCurrencyCode = sessionCurrencyCode
        self.isStarted = isStarted
        self.isHostLocally = isHostLocally
        self.seatsData = (try? JSONEncoder().encode(OpenTableSeatsPacking.players(in: seats))) ?? Data()
        self.anteAmount = anteAmount
        self.handData = hand.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
