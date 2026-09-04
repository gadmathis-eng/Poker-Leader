import Foundation
import SwiftData

struct SharedTableSeat: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var seatNumber: Int
    var playerName: String
    var handle: String?
    var playerKey: String
    var amount: String
    var isHost: Bool

    var amountDecimal: Decimal {
        Decimal(string: amount) ?? 0
    }
}

enum SharedTableSeatingError: LocalizedError, Equatable {
    case invalidSeat
    case seatTaken

    var errorDescription: String? {
        switch self {
        case .invalidSeat:
            "That seat is not on this table."
        case .seatTaken:
            "That seat is already taken."
        }
    }

    static func matching(_ error: Error) -> SharedTableSeatingError? {
        if let seating = error as? SharedTableSeatingError {
            return seating
        }

        let text = [
            error.localizedDescription,
            String(describing: error)
        ]
        .joined(separator: " ")
        .lowercased()
        if text.contains("seat taken") {
            return .seatTaken
        }
        if text.contains("invalid seat") {
            return .invalidSeat
        }
        return nil
    }
}

enum SharedTableSeating {
    static let seatCount = 8

    static func occupy(
        seats: [SharedTableSeat],
        seatNumber: Int,
        playerKey: String,
        playerName: String,
        handle: String?,
        amount: Decimal,
        isHost: Bool
    ) throws -> [SharedTableSeat] {
        guard (1...seatCount).contains(seatNumber) else {
            throw SharedTableSeatingError.invalidSeat
        }

        if seats.contains(where: { $0.seatNumber == seatNumber && $0.playerKey != playerKey }) {
            throw SharedTableSeatingError.seatTaken
        }

        var next = seats.filter { $0.playerKey != playerKey }
        let existing = seats.first(where: { $0.playerKey == playerKey })
        next.append(
            SharedTableSeat(
                id: existing?.id ?? UUID(),
                seatNumber: seatNumber,
                playerName: playerName,
                handle: handle,
                playerKey: playerKey,
                amount: NSDecimalNumber(decimal: amount.clampedToNonNegative).stringValue,
                isHost: isHost
            )
        )
        return next.sorted { $0.seatNumber < $1.seatNumber }
    }
}

@Model
final class OpenTableModel {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var inviteCode: String
    var hostDisplayName: String
    var hostPlayerKey: String
    var sessionCurrencyCode: String
    var isStarted: Bool
    var isHostLocally: Bool
    var seatsData: Data
    var createdAt: Date
    var updatedAt: Date

    var seats: [SharedTableSeat] {
        get {
            guard !seatsData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([SharedTableSeat].self, from: seatsData)) ?? []
        }
        set {
            seatsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            updatedAt = .now
        }
    }

    init(
        id: UUID = UUID(),
        inviteCode: String,
        hostDisplayName: String,
        hostPlayerKey: String,
        sessionCurrencyCode: String,
        isStarted: Bool = false,
        isHostLocally: Bool,
        seats: [SharedTableSeat] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.inviteCode = TableInviteDeepLink.normalizedCode(inviteCode)
        self.hostDisplayName = hostDisplayName
        self.hostPlayerKey = hostPlayerKey
        self.sessionCurrencyCode = sessionCurrencyCode
        self.isStarted = isStarted
        self.isHostLocally = isHostLocally
        self.seatsData = (try? JSONEncoder().encode(seats)) ?? Data()
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
