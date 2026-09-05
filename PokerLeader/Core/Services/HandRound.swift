import Foundation

enum HandRoundError: LocalizedError, Equatable {
    case notEnoughPlayers
    case notYourTurn
    case bettingClosed
    case handInProgress
    case betTooSmall
    case moveNotAllowed

    var errorDescription: String? {
        switch self {
        case .notEnoughPlayers:
            "Two players need money on the table to deal a hand."
        case .notYourTurn:
            "It is not your turn yet."
        case .bettingClosed:
            "The betting on this street is already done."
        case .handInProgress:
            "The hand is still being played."
        case .betTooSmall:
            "A bet has to be more than the table has already put in. Call instead, or raise it."
        case .moveNotAllowed:
            "That move is not available right now."
        }
    }
}

enum HandMove: String, Codable, Equatable {
    /// Ante up, or match whatever the table has bet, to stay in the hand.
    case call
    /// A bet or a raise, sized as the total this player wants in front of them
    /// on this street.
    case bet
    case check
    case fold
}

/// Deals and plays a hand of Texas hold'em on a shared table: two cards each, an
/// ante round, then the flop, the turn, and the river, each with a bet, check, or
/// fold, and a showdown that pays the pot to the best hand.
enum HandRound {
    static let holeCardCount = 2

    // MARK: - Seats and the button

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

    // MARK: - Dealing

    static func start(
        seats: [SharedTableSeat],
        dealerSeat: Int?,
        ante: Decimal,
        handNumber: Int = 1,
        id: UUID = UUID(),
        deck: [PlayingCard] = CardDeck.shuffled()
    ) throws -> SharedTableHand {
        let players = playableSeats(seats)
        guard players.count > 1 else { throw HandRoundError.notEnoughPlayers }

        let resolvedDealer = players.contains(where: { $0.seatNumber == dealerSeat })
            ? (dealerSeat ?? players[0].seatNumber)
            : (openingDealerSeat(seats: seats) ?? players[0].seatNumber)

        var hand = SharedTableHand(
            id: id,
            handNumber: Swift.max(handNumber, 1),
            revision: 1,
            dealerSeat: resolvedDealer,
            ante: TableMoney.string(ante),
            deck: deck,
            seats: players.map { seat in
                SharedTableHandSeat(
                    id: UUID(),
                    seatNumber: seat.seatNumber,
                    playerKey: seat.playerKey,
                    playerName: seat.playerName,
                    stack: TableMoney.string(seat.amountDecimal),
                    committed: "0"
                )
            }
        )

        dealHoleCards(in: &hand)
        hand.actingSeat = firstToAct(in: hand)
        if hand.actingSeat == nil {
            closeStreet(in: &hand)
        }
        return hand
    }

    /// One card at a time around the table, twice, starting left of the dealer.
    private static func dealHoleCards(in hand: inout SharedTableHand) {
        let order = actionOrder(seatNumbers: hand.seats.map(\.seatNumber), dealerSeat: hand.dealerSeat)
        for _ in 0..<holeCardCount {
            for seatNumber in order {
                guard let card = draw(from: &hand) else { return }
                guard let index = hand.seats.firstIndex(where: { $0.seatNumber == seatNumber }) else { continue }
                hand.seats[index].cards.append(card)
            }
        }
    }

    private static func draw(from hand: inout SharedTableHand) -> PlayingCard? {
        guard !hand.deck.isEmpty else { return nil }
        return hand.deck.removeFirst()
    }

    // MARK: - Betting

    static func apply(
        move: HandMove,
        amount: Decimal? = nil,
        playerKey: String,
        to hand: SharedTableHand
    ) throws -> SharedTableHand {
        guard let actingSeat = hand.actingSeat else { throw HandRoundError.bettingClosed }
        guard let index = hand.seats.firstIndex(where: { $0.playerKey == playerKey }),
              hand.seats[index].seatNumber == actingSeat else {
            throw HandRoundError.notYourTurn
        }

        var next = hand
        var seat = next.seats[index]
        let callTarget = hand.callTarget
        let toCall = hand.amountToCall(forPlayerKey: playerKey)

        switch move {
        case .fold:
            seat.isFolded = true
        case .check:
            guard toCall == 0 else { throw HandRoundError.moveNotAllowed }
        case .call:
            commit(toCall, to: &seat)
        case .bet:
            let requested = (amount ?? 0).clampedToNonNegative.roundedToHundredths
            let target = Swift.min(requested, seat.streetCap)
            let isAllIn = target == seat.streetCap
            guard target > seat.streetCommittedDecimal, target > callTarget || isAllIn else {
                throw HandRoundError.betTooSmall
            }
            commit(target - seat.streetCommittedDecimal, to: &seat)
        }

        seat.hasActed = true
        next.seats[index] = seat

        if seat.streetCommittedDecimal > callTarget {
            for other in next.seats.indices where other != index && !next.seats[other].isFolded {
                next.seats[other].hasActed = false
            }
        }

        next.revision += 1
        advance(in: &next, after: actingSeat)
        return next
    }

    private static func commit(_ amount: Decimal, to seat: inout SharedTableHandSeat) {
        let added = Swift.min(amount.clampedToNonNegative, seat.remaining)
        seat.committed = TableMoney.string(seat.committedDecimal + added)
        seat.streetCommitted = TableMoney.string(seat.streetCommittedDecimal + added)
    }


    /// Folds a player who has walked away from the table so the hand keeps
    /// moving instead of waiting on a seat nobody is sitting in. Whatever they
    /// already put in stays in the pot. Nil when they were not in this hand.
    static func withdraw(playerKey: String, from hand: SharedTableHand) -> SharedTableHand? {
        guard !hand.isComplete else { return nil }
        guard let index = hand.seats.firstIndex(where: { $0.playerKey == playerKey }),
              !hand.seats[index].isFolded else {
            return nil
        }

        let seatNumber = hand.seats[index].seatNumber
        var next = hand
        next.seats[index].isFolded = true
        next.seats[index].hasActed = true
        next.revision += 1

        if next.contenders.count < 2 {
            next.actingSeat = nil
            closeStreet(in: &next)
        } else if hand.actingSeat == seatNumber {
            advance(in: &next, after: seatNumber)
        }

        return next
    }

    // MARK: - Moving the hand on

    private static func advance(in hand: inout SharedTableHand, after seatNumber: Int?) {
        hand.actingSeat = nextActingSeat(in: hand, after: seatNumber)
        guard hand.actingSeat == nil else { return }
        closeStreet(in: &hand)
    }

    /// Everyone has answered the betting, so the pot is pulled in and the next
    /// cards go face up — or the hand is over.
    private static func closeStreet(in hand: inout SharedTableHand) {
        hand.actingSeat = nil

        guard hand.contenders.count > 1 else {
            finishByFold(in: &hand)
            return
        }

        var street = hand.street
        while let following = street.next, following != .showdown {
            street = following
            open(street, in: &hand)
            if let next = firstToAct(in: hand) {
                hand.actingSeat = next
                return
            }
        }

        showdown(in: &hand)
    }

    /// Turns the next cards face up and wipes the street's bets so the table can
    /// check or bet again.
    private static func open(_ street: HandStreet, in hand: inout SharedTableHand) {
        hand.street = street
        while hand.board.count < street.boardCount, let card = draw(from: &hand) {
            hand.board.append(card)
        }
        for index in hand.seats.indices {
            hand.seats[index].streetCommitted = "0"
            hand.seats[index].hasActed = false
        }
    }

    /// The first player left of the dealer who still has chips to bet. Nil when
    /// fewer than two players can act, so there is nothing left to bet.
    private static func firstToAct(in hand: SharedTableHand) -> Int? {
        let able = hand.contenders.filter { $0.remaining > 0 }
        guard able.count > 1 else { return nil }
        return nextActingSeat(in: hand, after: nil)
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
        return !seat.hasActed || seat.streetCommittedDecimal < callTarget
    }

    // MARK: - Paying out

    private static func finishByFold(in hand: inout SharedTableHand) {
        pay(pots: sidePots(in: hand), ranks: [:], in: &hand)
        if hand.winnerSeats.isEmpty {
            // Everyone folded before a penny went in, so there is nothing to
            // push, but the last player still won the hand.
            hand.winnerSeats = hand.contenders.map(\.seatNumber)
        }
        hand.isComplete = true
        hand.isRevealed = false
        hand.resultSummary = hand.seats.count > 1 ? "Everyone else folded." : nil
    }

    /// Cards on their backs: the best five-card hand takes the pot, and two of
    /// the same hand split it.
    private static func showdown(in hand: inout SharedTableHand) {
        hand.street = .showdown
        hand.isRevealed = true

        var ranks: [Int: PokerHandRank] = [:]
        for seat in hand.contenders {
            guard let rank = PokerHandEvaluator.best(from: seat.cards + hand.board) else { continue }
            ranks[seat.seatNumber] = rank
            guard let index = hand.seats.firstIndex(where: { $0.seatNumber == seat.seatNumber }) else { continue }
            hand.seats[index].handSummary = rank.summary
        }

        pay(pots: sidePots(in: hand), ranks: ranks, in: &hand)
        hand.isComplete = true
        hand.resultSummary = hand.winnerSeats
            .compactMap { ranks[$0]?.summary }
            .first
    }

    /// Pushes every pot to whoever has the best hand in it, and records who was
    /// paid so the table can be told who won.
    private static func pay(pots: [SidePot], ranks: [Int: PokerHandRank], in hand: inout SharedTableHand) {
        var awarded: [Int: Decimal] = [:]
        var winnerSeats: [Int] = []

        for pot in pots {
            let winners = bestSeats(among: pot.eligibleSeats, ranks: ranks, in: hand)
            guard !winners.isEmpty else { continue }
            for (winner, share) in zip(winners, TableMoney.shares(of: pot.amount, ways: winners.count)) {
                awarded[winner, default: 0] += share
                if !winnerSeats.contains(winner) {
                    winnerSeats.append(winner)
                }
            }
        }

        for index in hand.seats.indices {
            let amount = awarded[hand.seats[index].seatNumber] ?? 0
            hand.seats[index].awarded = TableMoney.string(amount)
        }
        hand.winnerSeats = winnerSeats.sorted()
    }

    /// The players in a pot with the best hand. Whoever is left when everyone
    /// folds wins it without showing anything.
    private static func bestSeats(
        among seatNumbers: [Int],
        ranks: [Int: PokerHandRank],
        in hand: SharedTableHand
    ) -> [Int] {
        let live = seatNumbers.filter { hand.seat(at: $0)?.isFolded == false }
        guard live.count > 1 else { return live }

        let ranked = live.compactMap { seatNumber in ranks[seatNumber].map { (seatNumber, $0) } }
        guard let best = ranked.map(\.1).max() else { return live }

        let winners = ranked.filter { !($0.1 < best) && !(best < $0.1) }.map(\.0)
        return orderedFromTheDealer(winners, in: hand)
    }

    /// Split pots hand the odd penny to the first player left of the dealer.
    private static func orderedFromTheDealer(_ seatNumbers: [Int], in hand: SharedTableHand) -> [Int] {
        let order = actionOrder(seatNumbers: hand.seats.map(\.seatNumber), dealerSeat: hand.dealerSeat)
        return seatNumbers.sorted { left, right in
            (order.firstIndex(of: left) ?? left) < (order.firstIndex(of: right) ?? right)
        }
    }

    private struct SidePot {
        var amount: Decimal
        var eligibleSeats: [Int]
    }

    /// The main pot, plus a side pot for every player who went all in for less,
    /// so nobody wins money they were not matched for.
    private static func sidePots(in hand: SharedTableHand) -> [SidePot] {
        let contenders = hand.contenders
        guard !contenders.isEmpty else { return [] }

        let eligibleSeats = contenders.map(\.seatNumber)
        let levels = Set(contenders.map(\.committedDecimal)).filter { $0 > 0 }.sorted()
        var pots: [SidePot] = []
        var previous: Decimal = 0

        for level in levels {
            let amount = hand.seats.reduce(Decimal(0)) { total, seat in
                total + (Swift.min(seat.committedDecimal, level) - previous).clampedToNonNegative
            }
            let eligible = contenders.filter { $0.committedDecimal >= level }.map(\.seatNumber)
            if amount > 0 {
                pots.append(SidePot(amount: amount, eligibleSeats: eligible))
            }
            previous = level
        }

        // Chips nobody was asked to match — a player who bet and then walked
        // away, say — go with the last pot rather than vanishing.
        let leftover = hand.seats.reduce(Decimal(0)) { total, seat in
            total + (seat.committedDecimal - previous).clampedToNonNegative
        }
        if leftover > 0 {
            if pots.isEmpty {
                pots.append(SidePot(amount: leftover, eligibleSeats: eligibleSeats))
            } else {
                pots[pots.count - 1].amount += leftover
            }
        }

        return pots
    }


    /// Every player's stack once the pot has been pushed to the winner. Reading
    /// it twice gives the same answer, so any phone can settle the hand.
    static func stacksAfter(_ hand: SharedTableHand) -> [String: Decimal] {
        var stacks: [String: Decimal] = [:]
        for seat in hand.seats {
            stacks[seat.playerKey] = (seat.remaining + seat.awardedDecimal).roundedToHundredths
        }
        return stacks
    }


    // MARK: - Bet sizing

    /// The smallest total a bet or raise can be made to on this street.
    static func minimumBet(in hand: SharedTableHand, forPlayerKey playerKey: String) -> Decimal {
        guard let seat = hand.seat(forPlayerKey: playerKey) else { return 0 }
        return Swift.min(hand.callTarget + TableMoney.penny, seat.streetCap)
    }

    /// A sensible opening size for the bet keypad: twice what is in front of the
    /// table, or half the pot when nobody has bet yet.
    static func suggestedBet(in hand: SharedTableHand, forPlayerKey playerKey: String) -> Decimal {
        guard let seat = hand.seat(forPlayerKey: playerKey) else { return 0 }
        let base = hand.callTarget > 0
            ? (hand.callTarget * 2).roundedToHundredths
            : (hand.pot / 2).roundedToHundredths
        let target = Swift.max(base, minimumBet(in: hand, forPlayerKey: playerKey))
        return Swift.min(target, seat.streetCap)
    }

    private static func playableSeats(_ seats: [SharedTableSeat]) -> [SharedTableSeat] {
        OpenTableSeatsPacking.players(in: seats)
            .filter { $0.amountDecimal > 0 }
    }
}
