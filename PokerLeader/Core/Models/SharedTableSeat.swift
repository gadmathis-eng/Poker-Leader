import Foundation

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

enum TableNaming {
    static func normalized(_ name: String?) -> String? {
        guard
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    static func title(name: String?, inviteCode: String) -> String {
        normalized(name) ?? "Table \(TableInviteDeepLink.normalizedCode(inviteCode))"
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

        var next = OpenTableSeatsPacking.players(in: seats).filter { $0.playerKey != playerKey }
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

    static func removing(playerKey: String, from seats: [SharedTableSeat]) -> [SharedTableSeat] {
        OpenTableSeatsPacking.players(in: seats).filter { $0.playerKey != playerKey }
    }
}
