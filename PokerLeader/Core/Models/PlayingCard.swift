import Foundation

enum CardSuit: String, Codable, CaseIterable, Hashable {
    case spades = "s"
    case hearts = "h"
    case diamonds = "d"
    case clubs = "c"

    var symbol: String {
        switch self {
        case .spades: "♠"
        case .hearts: "♥"
        case .diamonds: "♦"
        case .clubs: "♣"
        }
    }

    var isRed: Bool {
        self == .hearts || self == .diamonds
    }

    var name: String {
        switch self {
        case .spades: "spades"
        case .hearts: "hearts"
        case .diamonds: "diamonds"
        case .clubs: "clubs"
        }
    }
}

/// One card out of a 52-card deck. Stored as a two-character code such as `As`
/// or `Th` so a dealt hand stays small and readable in the cloud row.
struct PlayingCard: Codable, Equatable, Hashable, Identifiable, CustomStringConvertible {
    /// 2 through 10, then 11 jack, 12 queen, 13 king, 14 ace.
    var rank: Int
    var suit: CardSuit

    static let lowestRank = 2
    static let highestRank = 14

    init(rank: Int, suit: CardSuit) {
        self.rank = Swift.min(Swift.max(rank, Self.lowestRank), Self.highestRank)
        self.suit = suit
    }

    init?(code: String) {
        let characters = Array(code)
        guard characters.count == 2 else { return nil }
        guard let rank = Self.rank(forSymbol: String(characters[0])) else { return nil }
        guard let suit = CardSuit(rawValue: String(characters[1]).lowercased()) else { return nil }
        self.init(rank: rank, suit: suit)
    }

    var id: String { code }

    var code: String { "\(rankSymbol)\(suit.rawValue)" }

    var description: String { code }


    var rankSymbol: String {
        switch rank {
        case 14: "A"
        case 13: "K"
        case 12: "Q"
        case 11: "J"
        case 10: "T"
        default: String(rank)
        }
    }

    var rankName: String {
        switch rank {
        case 14: "ace"
        case 13: "king"
        case 12: "queen"
        case 11: "jack"
        case 10: "ten"
        case 9: "nine"
        case 8: "eight"
        case 7: "seven"
        case 6: "six"
        case 5: "five"
        case 4: "four"
        case 3: "three"
        default: "two"
        }
    }

    var rankNamePlural: String {
        rank == 6 ? "sixes" : "\(rankName)s"
    }

    var isRed: Bool { suit.isRed }

    /// Reads out loud for VoiceOver, such as "ace of spades".
    var accessibilityName: String {
        "\(rankName) of \(suit.name)"
    }


    static func rank(forSymbol symbol: String) -> Int? {
        switch symbol.uppercased() {
        case "A": 14
        case "K": 13
        case "Q": 12
        case "J": 11
        case "T", "10": 10
        default: Int(symbol).flatMap { (2...9).contains($0) ? $0 : nil }
        }
    }

    static func name(forRank rank: Int) -> String {
        PlayingCard(rank: rank, suit: .spades).rankName
    }

    static func pluralName(forRank rank: Int) -> String {
        PlayingCard(rank: rank, suit: .spades).rankNamePlural
    }

    init(from decoder: Decoder) throws {
        let code = try decoder.singleValueContainer().decode(String.self)
        guard let card = PlayingCard(code: code) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "\(code) is not a card"
                )
            )
        }
        self = card
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(code)
    }
}

enum CardDeck {
    static let cardCount = 52

    static var ordered: [PlayingCard] {
        CardSuit.allCases.flatMap { suit in
            (PlayingCard.lowestRank...PlayingCard.highestRank).map { PlayingCard(rank: $0, suit: suit) }
        }
    }

    static func shuffled() -> [PlayingCard] {
        ordered.shuffled()
    }

    /// A deck built from card codes, used by the tests to deal a known hand.
    static func deck(_ codes: [String]) -> [PlayingCard] {
        codes.compactMap(PlayingCard.init(code:))
    }
}
