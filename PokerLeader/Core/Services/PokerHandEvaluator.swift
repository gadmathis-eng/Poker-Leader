import Foundation

enum PokerHandCategory: Int, Comparable, Codable, CaseIterable {
    case highCard = 1
    case pair
    case twoPair
    case threeOfAKind
    case straight
    case flush
    case fullHouse
    case fourOfAKind
    case straightFlush

    var name: String {
        switch self {
        case .highCard: "High card"
        case .pair: "Pair"
        case .twoPair: "Two pair"
        case .threeOfAKind: "Three of a kind"
        case .straight: "Straight"
        case .flush: "Flush"
        case .fullHouse: "Full house"
        case .fourOfAKind: "Four of a kind"
        case .straightFlush: "Straight flush"
        }
    }

    static func < (lhs: PokerHandCategory, rhs: PokerHandCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The five cards a player ends up showing, and how they beat the next player.
struct PokerHandRank: Comparable, Equatable {
    var category: PokerHandCategory
    /// The ranks that break a tie inside a category, best first.
    var tiebreakers: [Int]
    var cards: [PlayingCard]

    /// Reads like "Full house, kings full of twos".
    var summary: String {
        switch category {
        case .straightFlush:
            return tiebreakers.first == PlayingCard.highestRank
                ? "Royal flush"
                : "Straight flush, \(name(0)) high"
        case .fourOfAKind:
            return "Four of a kind, \(plural(0))"
        case .fullHouse:
            return "Full house, \(plural(0)) full of \(plural(1))"
        case .flush:
            return "Flush, \(name(0)) high"
        case .straight:
            return "Straight, \(name(0)) high"
        case .threeOfAKind:
            return "Three of a kind, \(plural(0))"
        case .twoPair:
            return "Two pair, \(plural(0)) and \(plural(1))"
        case .pair:
            return "Pair of \(plural(0))"
        case .highCard:
            return "\(name(0).capitalized) high"
        }
    }

    static func < (lhs: PokerHandRank, rhs: PokerHandRank) -> Bool {
        if lhs.category != rhs.category {
            return lhs.category < rhs.category
        }
        for (left, right) in zip(lhs.tiebreakers, rhs.tiebreakers) where left != right {
            return left < right
        }
        return false
    }

    private func name(_ index: Int) -> String {
        guard index < tiebreakers.count else { return "" }
        return PlayingCard.name(forRank: tiebreakers[index])
    }


    private func plural(_ index: Int) -> String {
        guard index < tiebreakers.count else { return "" }
        return PlayingCard.pluralName(forRank: tiebreakers[index])
    }
}

enum PokerHandEvaluator {
    static let handSize = 5

    /// The best five-card hand out of everything a player can see: their two
    /// cards and the board. Nil when there are not five cards yet.
    static func best(from cards: [PlayingCard]) -> PokerHandRank? {
        let unique = deduplicated(cards)
        guard unique.count >= handSize else { return nil }
        if unique.count == handSize {
            return rank(of: unique)
        }
        return combinations(of: unique, choose: handSize)
            .compactMap(rank(of:))
            .max()
    }

    /// What two cards are called before there is a board to read, such as
    /// "Pair of queens" or "Ace king suited".
    static func startingHandName(_ cards: [PlayingCard]) -> String? {
        let sorted = cards.sorted { $0.rank > $1.rank }
        guard sorted.count == 2, let high = sorted.first, let low = sorted.last else { return nil }

        if high.rank == low.rank {
            return "Pair of \(high.rankNamePlural)"
        }
        return "\(high.rankName.capitalized) \(low.rankName) \(high.suit == low.suit ? "suited" : "offsuit")"
    }

    /// The five-card hand these exact cards make.
    static func rank(of cards: [PlayingCard]) -> PokerHandRank? {
        guard cards.count == handSize else { return nil }

        let sorted = cards.sorted { $0.rank > $1.rank }
        let isFlush = Set(sorted.map(\.suit)).count == 1
        let straight = straightHigh(in: sorted)

        if let straightHigh = straight {
            let ordered = straightOrder(sorted, high: straightHigh)
            return PokerHandRank(
                category: isFlush ? .straightFlush : .straight,
                tiebreakers: [straightHigh],
                cards: ordered
            )
        }

        let groups = rankGroups(in: sorted)

        if isFlush {
            return PokerHandRank(category: .flush, tiebreakers: sorted.map(\.rank), cards: sorted)
        }

        let counts = groups.map(\.cards.count)
        let ordered = groups.flatMap(\.cards)
        let tiebreakers = groups.map(\.rank)

        switch counts {
        case [4, 1]:
            return PokerHandRank(category: .fourOfAKind, tiebreakers: tiebreakers, cards: ordered)
        case [3, 2]:
            return PokerHandRank(category: .fullHouse, tiebreakers: tiebreakers, cards: ordered)
        case [3, 1, 1]:
            return PokerHandRank(category: .threeOfAKind, tiebreakers: tiebreakers, cards: ordered)
        case [2, 2, 1]:
            return PokerHandRank(category: .twoPair, tiebreakers: tiebreakers, cards: ordered)
        case [2, 1, 1, 1]:
            return PokerHandRank(category: .pair, tiebreakers: tiebreakers, cards: ordered)
        default:
            return PokerHandRank(category: .highCard, tiebreakers: tiebreakers, cards: ordered)
        }
    }

    private struct RankGroup {
        var rank: Int
        var cards: [PlayingCard]
    }

    /// Cards bunched up by rank: the biggest bunch first, then the highest rank,
    /// which is the order a hand is read out in.
    private static func rankGroups(in cards: [PlayingCard]) -> [RankGroup] {
        Dictionary(grouping: cards, by: \.rank)
            .map { RankGroup(rank: $0.key, cards: $0.value) }
            .sorted { left, right in
                if left.cards.count != right.cards.count {
                    return left.cards.count > right.cards.count
                }
                return left.rank > right.rank
            }
    }

    /// The top card of a straight, counting the wheel (A-2-3-4-5) as five high.
    private static func straightHigh(in sorted: [PlayingCard]) -> Int? {
        let ranks = Set(sorted.map(\.rank))
        guard ranks.count == handSize else { return nil }
        guard let high = ranks.max(), let low = ranks.min() else { return nil }
        if high - low == handSize - 1 {
            return high
        }
        let wheel: Set<Int> = [14, 2, 3, 4, 5]
        return ranks == wheel ? 5 : nil
    }

    /// A straight is read from its top card down, so the wheel's ace comes last.
    private static func straightOrder(_ sorted: [PlayingCard], high: Int) -> [PlayingCard] {
        guard high == 5 else { return sorted }
        return sorted.filter { $0.rank != PlayingCard.highestRank }
            + sorted.filter { $0.rank == PlayingCard.highestRank }
    }

    private static func deduplicated(_ cards: [PlayingCard]) -> [PlayingCard] {
        var seen: Set<PlayingCard> = []
        return cards.filter { seen.insert($0).inserted }
    }

    private static func combinations(of cards: [PlayingCard], choose count: Int) -> [[PlayingCard]] {
        guard count > 0 else { return [[]] }
        guard cards.count >= count else { return [] }
        if cards.count == count { return [cards] }

        let first = cards[0]
        let rest = Array(cards.dropFirst())
        return combinations(of: rest, choose: count - 1).map { [first] + $0 }
            + combinations(of: rest, choose: count)
    }
}
