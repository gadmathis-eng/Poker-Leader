import Foundation

/// Everything the table screen has to say about the hand in front of you: whose
/// turn it is, what you are holding, and how the hand ended. It lives apart from
/// the view so one place decides the wording and it can be checked without a
/// simulator.
struct HandNarration {
    /// What the player can do right now, which is also what the table screen
    /// puts buttons on.
    enum Turn: Equatable {
        /// No hand yet — the table is waiting for a second player with money on it.
        case waitingForPlayers
        /// You sat down after the cards went out.
        case notDealtIn
        /// Your move. `toCall` is zero when nothing is owed.
        case toAct(toCall: Decimal)
        case folded
        case waitingForOthers
        case handOver
    }

    let hand: SharedTableHand?
    let localPlayerKey: String
    let currencyCode: String

    private var localSeat: SharedTableHandSeat? {
        hand?.seat(forPlayerKey: localPlayerKey)
    }

    private var toCall: Decimal {
        hand?.amountToCall(forPlayerKey: localPlayerKey) ?? 0
    }

    var turn: Turn {
        guard let hand else { return .waitingForPlayers }
        if hand.isComplete { return .handOver }
        guard let seat = localSeat else { return .notDealtIn }
        if seat.isFolded { return .folded }
        if hand.isActing(playerKey: localPlayerKey) { return .toAct(toCall: toCall) }
        return .waitingForOthers
    }

    /// What your two cards and the cards on the table add up to right now.
    var yourHand: String? {
        guard let seat = localSeat, seat.isDealtCards, !seat.isFolded else { return nil }
        let board = hand?.board ?? []
        if let rank = PokerHandEvaluator.best(from: seat.cards + board) {
            return rank.summary
        }
        return PokerHandEvaluator.startingHandName(seat.cards)
    }

    /// The line above the cards in the middle of the table.
    var boardTitle: String {
        guard let hand else { return "Waiting for players" }
        return hand.isComplete
            ? "Hand \(hand.handNumber)"
            : "Hand \(hand.handNumber) · \(hand.street.title)"
    }

    /// The line under the pot: who everyone is waiting for, or who won.
    var boardStatus: String {
        guard let hand else { return "" }
        if hand.isComplete {
            let winners = hand.winners
            if winners.count > 1 { return "Split pot" }
            if let winner = winners.first { return "\(winner.playerName) wins" }
            return "Hand over"
        }
        if case .toAct = turn { return "Your turn" }
        return waitingLine
    }

    var title: String {
        guard let hand else { return "Waiting for players" }
        switch turn {
        case .handOver:
            return resultTitle(for: hand)
        case .toAct:
            return turnTitle(for: hand)
        case .notDealtIn:
            return "You are in from the next hand"
        case .folded:
            return "You folded"
        case .waitingForOthers, .waitingForPlayers:
            return waitingLine
        }
    }

    var detail: String {
        guard let hand else {
            return "Share the table so a friend can sit down. The first hand deals as soon as two of you have money on the table."
        }
        switch turn {
        case .handOver:
            return hand.resultSummary ?? "Pot pushed to the winner."
        case .toAct:
            return turnDetail(for: hand)
        case .notDealtIn:
            return "This hand started before you sat down."
        case .folded:
            return waitingLine
        case .waitingForOthers:
            return "You are in for \(money(localSeat?.committedDecimal ?? 0))."
        case .waitingForPlayers:
            return ""
        }
    }

    /// The stake and what is left behind you, shown under the buttons so the
    /// prompt itself stays to one line.
    var stackLine: String? {
        guard let hand, !hand.isComplete, let seat = localSeat else { return nil }
        var parts = ["Ante \(money(hand.anteDecimal))", "\(money(seat.remaining)) behind"]
        if seat.toppedUpDecimal > 0 {
            parts.append("\(money(seat.toppedUpDecimal)) joins next hand")
        }
        return parts.joined(separator: " · ")
    }

    private var waitingLine: String {
        guard let name = hand?.actingSeatName else { return "Waiting for the table" }
        return "Waiting for \(name)"
    }

    private func turnTitle(for hand: SharedTableHand) -> String {
        switch hand.street {
        case .preflop:
            toCall > 0 ? "Are you in?" : "Your turn before the flop"
        case .flop, .turn, .river:
            "Your turn on the \(hand.street.title.lowercased())"
        case .showdown:
            "Cards up"
        }
    }

    private func turnDetail(for hand: SharedTableHand) -> String {
        var parts: [String] = []
        if let yourHand {
            parts.append(yourHand)
        }
        if toCall > 0 {
            let owed = money(toCall)
            parts.append(hand.callTarget == hand.anteDecimal ? "Ante \(owed) to stay in" : "\(owed) to call")
        } else {
            parts.append("Nothing to put in yet")
        }
        return parts.joined(separator: " · ")
    }

    private func resultTitle(for hand: SharedTableHand) -> String {
        let winners = hand.winners
        guard let first = winners.first else { return "Hand over" }

        if winners.count > 1 {
            let names = winners.map { $0.playerKey == localPlayerKey ? "You" : $0.playerName }
            let joined = names.count == 2
                ? names.joined(separator: " and ")
                : names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
            return "\(joined) split \(money(hand.pot))"
        }

        let who = first.playerKey == localPlayerKey ? "You take" : "\(first.playerName) takes"
        return "\(who) \(money(first.awardedDecimal))"
    }

    private func money(_ amount: Decimal) -> String {
        MoneyFormatting.plain(amount, currencyCode: currencyCode)
    }
}
