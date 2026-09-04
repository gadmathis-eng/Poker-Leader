import Foundation

enum TableMoney {
    static let penny = Decimal(sign: .plus, exponent: -2, significand: 1)

    static func string(_ amount: Decimal) -> String {
        NSDecimalNumber(decimal: amount.clampedToNonNegative.roundedToHundredths).stringValue
    }

    static func decimal(_ text: String) -> Decimal {
        Decimal(string: text) ?? 0
    }
}

enum TableAnte {
    static func defaultAmount(forBuyIn buyIn: Decimal) -> Decimal {
        let stack = buyIn.clampedToNonNegative
        guard stack > 0 else { return 0 }
        let hundredth = (stack / 100).roundedToHundredths
        return hundredth < TableMoney.penny ? TableMoney.penny : hundredth
    }
}

/// One player's position in the pre-flop round.
struct SharedTableHandSeat: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var seatNumber: Int
    var playerKey: String
    var playerName: String
    var stack: String
    var committed: String
    var hasActed: Bool
    var isFolded: Bool

    var stackDecimal: Decimal { TableMoney.decimal(stack) }
    var committedDecimal: Decimal { TableMoney.decimal(committed) }

    var remaining: Decimal {
        (stackDecimal - committedDecimal).clampedToNonNegative
    }

    var isAllIn: Bool {
        !isFolded && committedDecimal > 0 && remaining == 0
    }
}

/// The pre-flop betting round for a shared table. Cards stay on the real table;
/// this only tracks who is in the hand and what everyone has put in the pot.
struct SharedTableHand: Codable, Equatable, Hashable {
    var id: UUID
    var handNumber: Int
    var revision: Int
    var dealerSeat: Int
    var ante: String
    var actingSeat: Int?
    var winnerSeat: Int?
    var seats: [SharedTableHandSeat]

    var anteDecimal: Decimal { TableMoney.decimal(ante) }

    var pot: Decimal {
        seats.reduce(Decimal(0)) { $0 + $1.committedDecimal }
    }

    var highestCommitted: Decimal {
        seats.map(\.committedDecimal).max() ?? 0
    }

    /// What a player has to have in the pot to still be in the hand: the ante
    /// until somebody bets more than it.
    var callTarget: Decimal {
        Swift.max(highestCommitted, anteDecimal)
    }

    var contenders: [SharedTableHandSeat] {
        seats.filter { !$0.isFolded }
    }

    var isBettingComplete: Bool {
        actingSeat == nil
    }

    func seat(at seatNumber: Int) -> SharedTableHandSeat? {
        seats.first { $0.seatNumber == seatNumber }
    }

    func seat(forPlayerKey playerKey: String) -> SharedTableHandSeat? {
        seats.first { $0.playerKey == playerKey }
    }

    var actingSeatName: String? {
        actingSeat.flatMap { seat(at: $0)?.playerName }
    }

    func isActing(playerKey: String) -> Bool {
        guard let actingSeat, let seat = seat(forPlayerKey: playerKey) else { return false }
        return seat.seatNumber == actingSeat
    }

    /// What this player still has to put in to stay in the hand.
    func amountToCall(forPlayerKey playerKey: String) -> Decimal {
        guard let seat = seat(forPlayerKey: playerKey) else { return 0 }
        return Swift.min((callTarget - seat.committedDecimal).clampedToNonNegative, seat.remaining)
    }
}

enum PreflopRoundError: LocalizedError, Equatable {
    case notEnoughPlayers
    case notYourTurn
    case bettingClosed
    case bettingOpen
    case moveNotAllowed

    var errorDescription: String? {
        switch self {
        case .notEnoughPlayers:
            "Two players need money on the table to deal a hand."
        case .notYourTurn:
            "It is not your turn yet."
        case .bettingClosed:
            "Pre-flop betting is already done."
        case .bettingOpen:
            "The table is still betting."
        case .moveNotAllowed:
            "That move is not available right now."
        }
    }
}

enum PreflopMove: String, Codable, Equatable {
    /// Ante up, or match whatever the table has bet, to stay in the hand.
    case stayIn = "in"
    /// A pre-flop bet, sized as the total this player wants in the pot.
    case bet
    case check
    case fold
}

enum PreflopRound {
    static func openingDealerSeat(seats: [SharedTableSeat]) -> Int? {
        let players = playableSeats(seats)
        if let host = players.first(where: \.isHost) {
            return host.seatNumber
        }
        return players.first?.seatNumber
    }

    static func nextDealerSeat(after dealerSeat: Int, seats: [SharedTableSeat]) -> Int? {
        let numbers = playableSeats(seats).map(\.seatNumber)
        return actionOrder(seatNumbers: numbers, dealerSeat: dealerSeat).first
    }

    /// Seat numbers in the order they get asked, starting left of the dealer.
    static func actionOrder(seatNumbers: [Int], dealerSeat: Int) -> [Int] {
        let sorted = seatNumbers.sorted()
        guard let pivot = sorted.firstIndex(where: { $0 > dealerSeat }) else { return sorted }
        return Array(sorted[pivot...]) + Array(sorted[..<pivot])
    }

    static func start(
        seats: [SharedTableSeat],
        dealerSeat: Int?,
        ante: Decimal,
        handNumber: Int = 1,
        id: UUID = UUID()
    ) throws -> SharedTableHand {
        let players = playableSeats(seats)
        guard players.count > 1 else { throw PreflopRoundError.notEnoughPlayers }

        let resolvedDealer = players.contains(where: { $0.seatNumber == dealerSeat })
            ? (dealerSeat ?? players[0].seatNumber)
            : (openingDealerSeat(seats: seats) ?? players[0].seatNumber)

        var hand = SharedTableHand(
            id: id,
            handNumber: Swift.max(handNumber, 1),
            revision: 1,
            dealerSeat: resolvedDealer,
            ante: TableMoney.string(ante),
            actingSeat: nil,
            winnerSeat: nil,
            seats: players.map { seat in
                SharedTableHandSeat(
                    id: UUID(),
                    seatNumber: seat.seatNumber,
                    playerKey: seat.playerKey,
                    playerName: seat.playerName,
                    stack: TableMoney.string(seat.amountDecimal),
                    committed: "0",
                    hasActed: false,
                    isFolded: false
                )
            }
        )
        hand.actingSeat = nextActingSeat(in: hand, after: nil)
        hand.winnerSeat = automaticWinnerSeat(in: hand)
        return hand
    }

    static func apply(
        move: PreflopMove,
        amount: Decimal? = nil,
        playerKey: String,
        to hand: SharedTableHand
    ) throws -> SharedTableHand {
        guard let actingSeat = hand.actingSeat else { throw PreflopRoundError.bettingClosed }
        guard let index = hand.seats.firstIndex(where: { $0.playerKey == playerKey }),
              hand.seats[index].seatNumber == actingSeat else {
            throw PreflopRoundError.notYourTurn
        }

        var next = hand
        var seat = next.seats[index]
        let toCall = hand.amountToCall(forPlayerKey: playerKey)

        switch move {
        case .fold:
            seat.isFolded = true
        case .check:
            guard toCall == 0 else { throw PreflopRoundError.moveNotAllowed }
        case .stayIn:
            seat.committed = TableMoney.string(seat.committedDecimal + toCall)
        case .bet:
            let requested = (amount ?? 0).clampedToNonNegative.roundedToHundredths
            let target = Swift.min(requested, seat.stackDecimal)
            let isAllIn = target == seat.stackDecimal
            guard target > seat.committedDecimal, target > hand.callTarget || isAllIn else {
                throw PreflopRoundError.moveNotAllowed
            }
            seat.committed = TableMoney.string(target)
        }

        seat.hasActed = true
        next.seats[index] = seat

        if seat.committedDecimal > hand.callTarget {
            for other in next.seats.indices where other != index && !next.seats[other].isFolded {
                next.seats[other].hasActed = false
            }
        }

        next.revision += 1
        next.actingSeat = nextActingSeat(in: next, after: actingSeat)
        next.winnerSeat = automaticWinnerSeat(in: next)
        return next
    }

    static func award(potTo seatNumber: Int, in hand: SharedTableHand) throws -> SharedTableHand {
        guard hand.isBettingComplete else { throw PreflopRoundError.bettingOpen }
        guard let seat = hand.seat(at: seatNumber), !seat.isFolded else {
            throw PreflopRoundError.moveNotAllowed
        }

        var next = hand
        next.winnerSeat = seatNumber
        next.revision += 1
        return next
    }

    /// The smallest total a pre-flop bet can be raised to.
    static func minimumBet(in hand: SharedTableHand, forPlayerKey playerKey: String) -> Decimal {
        guard let seat = hand.seat(forPlayerKey: playerKey) else { return 0 }
        return Swift.min(hand.callTarget + TableMoney.penny, seat.stackDecimal)
    }

    /// A sensible opening size for the bet keypad: twice the table's ante or bet so far.
    static func suggestedBet(in hand: SharedTableHand, forPlayerKey playerKey: String) -> Decimal {
        guard let seat = hand.seat(forPlayerKey: playerKey) else { return 0 }
        let doubled = (hand.callTarget * 2).roundedToHundredths
        let target = Swift.max(doubled, minimumBet(in: hand, forPlayerKey: playerKey))
        return Swift.min(target, seat.stackDecimal)
    }

    /// Every player's stack once the pot has been pushed to the winner.
    static func stacksAfter(_ hand: SharedTableHand) -> [String: Decimal] {
        var stacks: [String: Decimal] = [:]
        for seat in hand.seats {
            stacks[seat.playerKey] = seat.remaining
        }
        if let winnerSeat = hand.winnerSeat, let winner = hand.seat(at: winnerSeat) {
            stacks[winner.playerKey] = (winner.remaining + hand.pot).roundedToHundredths
        }
        return stacks
    }

    private static func playableSeats(_ seats: [SharedTableSeat]) -> [SharedTableSeat] {
        seats
            .filter { $0.amountDecimal > 0 }
            .sorted { $0.seatNumber < $1.seatNumber }
    }

    private static func automaticWinnerSeat(in hand: SharedTableHand) -> Int? {
        guard hand.isBettingComplete else { return nil }
        guard hand.contenders.count == 1 else { return hand.winnerSeat }
        return hand.contenders[0].seatNumber
    }

    private static func nextActingSeat(in hand: SharedTableHand, after current: Int?) -> Int? {
        guard hand.contenders.count > 1 else { return nil }

        let order = actionOrder(seatNumbers: hand.seats.map(\.seatNumber), dealerSeat: hand.dealerSeat)
        guard !order.isEmpty else { return nil }

        let callTarget = hand.callTarget
        let start = current.flatMap { order.firstIndex(of: $0) }.map { $0 + 1 } ?? 0

        for offset in 0..<order.count {
            let seatNumber = order[(start + offset) % order.count]
            guard let seat = hand.seat(at: seatNumber) else { continue }
            if needsAction(seat, callTarget: callTarget) {
                return seatNumber
            }
        }
        return nil
    }

    private static func needsAction(_ seat: SharedTableHandSeat, callTarget: Decimal) -> Bool {
        guard !seat.isFolded, seat.remaining > 0 else { return false }
        return !seat.hasActed || seat.committedDecimal < callTarget
    }
}
