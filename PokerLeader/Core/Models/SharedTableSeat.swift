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

struct SessionTableSeat: Equatable {
    var playerKey: String
    var playerName: String
    var handle: String?
    var amount: Decimal
    var isHost: Bool
}

enum SessionTableSeating {
    /// Builds seats for a new table from the people toggled into a session.
    /// The host uses the local player key so this phone can act for them; everyone
    /// else keeps their member id. A zero money-in falls back to the buy-in so
    /// those players can be dealt in.
    static func seats(
        from members: [MemberModel],
        moneyIn: [UUID: Decimal],
        standardBuyIn: Decimal,
        hostMemberId: UUID?,
        hostPlayerKey: String,
        preferredHandle: String
    ) -> [SessionTableSeat] {
        let seatedMembers = Array(members.prefix(SharedTableSeating.seatCount))
        let hostId = seatedMembers.first(where: { $0.id == hostMemberId })?.id
            ?? seatedMembers.first(where: \.isCurrentUser)?.id

        return seatedMembers.map { member in
            let isHost = member.id == hostId
            let recorded = (moneyIn[member.id] ?? 0).clampedToNonNegative
            return SessionTableSeat(
                playerKey: isHost ? hostPlayerKey : member.id.uuidString,
                playerName: member.displayName(preferredHandle: preferredHandle),
                handle: MemberModel.normalizedHandle(member.handle)
                    ?? (member.isCurrentUser ? MemberModel.normalizedHandle(preferredHandle) : nil),
                amount: recorded > 0 ? recorded : standardBuyIn.clampedToNonNegative,
                isHost: isHost
            )
        }
    }
}
