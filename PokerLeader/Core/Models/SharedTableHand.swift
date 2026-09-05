import Foundation

enum TableMoney {
    static let penny = Decimal(sign: .plus, exponent: -2, significand: 1)

    static func string(_ amount: Decimal) -> String {
        NSDecimalNumber(decimal: amount.clampedToNonNegative.roundedToHundredths).stringValue
    }

    static func decimal(_ text: String) -> Decimal {
        Decimal(string: text) ?? 0
    }

    /// Splits a pot without inventing or losing a penny: the odd penny goes to
    /// the first share.
    static func shares(of amount: Decimal, ways: Int) -> [Decimal] {
        let total = amount.clampedToNonNegative.roundedToHundredths
        guard ways > 1 else { return [total] }

        var divided = total / Decimal(ways)
        var base = Decimal()
        NSDecimalRound(&base, &divided, 2, .down)

        var shares = Array(repeating: base, count: ways)
        shares[0] += total - base * Decimal(ways)
        return shares
    }
}

enum OpenTableSchema {
    /// True when the cloud rejected a write because the pre-flop columns are not
    /// there yet, which reads like: Could not find the 'hand' column of
    /// 'open_tables' in the schema cache.
    static func isMissingHandColumn(_ error: Error) -> Bool {
        let text = describe(error)
        guard text.contains("ante_amount") || text.contains("'hand'") || text.contains("\"hand\"") else {
            return false
        }
        return text.contains("column") || text.contains("schema cache")
    }

    /// True when the whole `open_tables` table is missing, rather than one column.
    static func isMissingTable(_ error: Error) -> Bool {
        let text = describe(error)
        guard text.contains("open_tables") else { return false }
        guard !isMissingHandColumn(error) else { return false }
        let looksMissing = text.contains("schema cache")
            || text.contains("could not find the table")
            || text.contains("does not exist")
        return looksMissing && !text.contains("column")
    }

    /// True when the atomic seat-merge function is missing, which reads like:
    /// Could not find the function public.merge_open_table_seat in the schema cache.
    static func isMissingSeatMerge(_ error: Error) -> Bool {
        let text = describe(error)
        guard text.contains("merge_open_table_seat") else { return false }
        return text.contains("schema cache")
            || text.contains("could not find the function")
            || text.contains("does not exist")
            || text.contains("pgrst202")
    }

    private static func describe(_ error: Error) -> String {
        [
            error.localizedDescription,
            String(describing: error),
            (error as? LocalizedError)?.errorDescription,
            (error as? LocalizedError)?.failureReason
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    }
}

/// The ante and the hand in progress ride inside the existing `seats` JSON so a
/// live project that already has `open_tables` can share a hand without a new
/// column. The reserved marker looks like a seat to the seat-merge function,
/// which copies unknown array items through, and is stripped before the table
/// is shown.
enum OpenTableSeatsPacking {
    static let markerPlayerKey = "__potmaster_hand__"
    static let markerId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    static func isMarker(_ seat: SharedTableSeat) -> Bool {
        seat.playerKey == markerPlayerKey || seat.seatNumber < 1
    }

    static func players(in seats: [SharedTableSeat]) -> [SharedTableSeat] {
        seats
            .filter { !isMarker($0) }
            .sorted { $0.seatNumber < $1.seatNumber }
    }
}

/// One cloud `seats` value: the people at the table, plus an optional marker
/// that carries the ante and the hand when those columns are not on the row.
struct OpenTablePackedSeats: Codable, Equatable {
    var seats: [SharedTableSeat]
    var anteAmount: String
    var hand: SharedTableHand?

    init(seats: [SharedTableSeat], anteAmount: String, hand: SharedTableHand?) {
        self.seats = OpenTableSeatsPacking.players(in: seats)
        self.anteAmount = anteAmount
        self.hand = hand
    }

    init(from decoder: Decoder) throws {
        let items = try [OpenTableSeatItem](from: decoder)
        var players: [SharedTableSeat] = []
        var ante = "0"
        var packedHand: SharedTableHand?
        for item in items {
            switch item {
            case .player(let seat):
                players.append(seat)
            case .marker(let marker):
                ante = marker.anteAmount
                packedHand = marker.hand
            }
        }
        self.seats = OpenTableSeatsPacking.players(in: players)
        self.anteAmount = ante
        self.hand = packedHand
    }

    func encode(to encoder: Encoder) throws {
        var items = seats.map { OpenTableSeatItem.player($0) }
        items.append(.marker(OpenTableHandMarker(anteAmount: anteAmount, hand: hand)))
        try items.encode(to: encoder)
    }
}

private enum OpenTableSeatItem: Codable {
    case player(SharedTableSeat)
    case marker(OpenTableHandMarker)

    init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: OpenTableHandMarker.CodingKeys.self)
        let playerKey = try keyed.decode(String.self, forKey: .playerKey)
        if playerKey == OpenTableSeatsPacking.markerPlayerKey {
            self = .marker(try OpenTableHandMarker(from: decoder))
        } else {
            self = .player(try SharedTableSeat(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .player(let seat):
            try seat.encode(to: encoder)
        case .marker(let marker):
            try marker.encode(to: encoder)
        }
    }
}

private struct OpenTableHandMarker: Codable, Equatable {
    var id: UUID
    var seatNumber: Int
    var playerName: String
    var handle: String?
    var playerKey: String
    var amount: String
    var isHost: Bool
    var anteAmount: String
    var hand: SharedTableHand?

    enum CodingKeys: String, CodingKey {
        case id
        case seatNumber
        case playerName
        case handle
        case playerKey
        case amount
        case isHost
        case anteAmount
        case hand
    }

    init(anteAmount: String, hand: SharedTableHand?) {
        self.id = OpenTableSeatsPacking.markerId
        self.seatNumber = 0
        self.playerName = ""
        self.handle = nil
        self.playerKey = OpenTableSeatsPacking.markerPlayerKey
        self.amount = "0"
        self.isHost = false
        self.anteAmount = anteAmount
        self.hand = hand
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? OpenTableSeatsPacking.markerId
        seatNumber = try container.decodeIfPresent(Int.self, forKey: .seatNumber) ?? 0
        playerName = try container.decodeIfPresent(String.self, forKey: .playerName) ?? ""
        handle = try container.decodeIfPresent(String.self, forKey: .handle)
        playerKey = try container.decodeIfPresent(String.self, forKey: .playerKey) ?? OpenTableSeatsPacking.markerPlayerKey
        amount = try container.decodeIfPresent(String.self, forKey: .amount) ?? "0"
        isHost = try container.decodeIfPresent(Bool.self, forKey: .isHost) ?? false
        anteAmount = try container.decodeIfPresent(String.self, forKey: .anteAmount) ?? "0"
        hand = try container.decodeIfPresent(SharedTableHand.self, forKey: .hand)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(seatNumber, forKey: .seatNumber)
        try container.encode(playerName, forKey: .playerName)
        try container.encodeIfPresent(handle, forKey: .handle)
        try container.encode(playerKey, forKey: .playerKey)
        try container.encode(amount, forKey: .amount)
        try container.encode(isHost, forKey: .isHost)
        try container.encode(anteAmount, forKey: .anteAmount)
        try container.encode(hand, forKey: .hand)
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

/// How far a hand has got: the ante round, then the three cards of the flop, the
/// turn, the river, and finally cards on their backs.
enum HandStreet: String, Codable, CaseIterable {
    case preflop
    case flop
    case turn
    case river
    case showdown

    var title: String {
        switch self {
        case .preflop: "Pre-flop"
        case .flop: "Flop"
        case .turn: "Turn"
        case .river: "River"
        case .showdown: "Showdown"
        }
    }

    /// How many cards are face up in the middle of the table on this street.
    var boardCount: Int {
        switch self {
        case .preflop: 0
        case .flop: 3
        case .turn: 4
        case .river, .showdown: 5
        }
    }

    var next: HandStreet? {
        switch self {
        case .preflop: .flop
        case .flop: .turn
        case .turn: .river
        case .river: .showdown
        case .showdown: nil
        }
    }

    /// True while the table can still be asked to bet, check, or fold.
    var isBettable: Bool {
        self != .showdown
    }
}

/// One player in the hand: their two cards, their stack, and what they have put
/// in the pot.
struct SharedTableHandSeat: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var seatNumber: Int
    var playerKey: String
    var playerName: String
    /// The stack this player sat down with at the start of the hand.
    var stack: String
    /// Everything this player has put in the pot this hand.
    var committed: String
    /// What this player has put in on the street being bet right now.
    var streetCommitted: String
    var hasActed: Bool
    var isFolded: Bool
    var cards: [PlayingCard]
    /// What the hand paid this player once it was over.
    var awarded: String
    /// The five cards this player showed down, such as "Flush, ace high".
    var handSummary: String?

    init(
        id: UUID,
        seatNumber: Int,
        playerKey: String,
        playerName: String,
        stack: String,
        committed: String,
        streetCommitted: String = "0",
        hasActed: Bool = false,
        isFolded: Bool = false,
        cards: [PlayingCard] = [],
        awarded: String = "0",
        handSummary: String? = nil
    ) {
        self.id = id
        self.seatNumber = seatNumber
        self.playerKey = playerKey
        self.playerName = playerName
        self.stack = stack
        self.committed = committed
        self.streetCommitted = streetCommitted
        self.hasActed = hasActed
        self.isFolded = isFolded
        self.cards = cards
        self.awarded = awarded
        self.handSummary = handSummary
    }

    var stackDecimal: Decimal { TableMoney.decimal(stack) }
    var committedDecimal: Decimal { TableMoney.decimal(committed) }
    var streetCommittedDecimal: Decimal { TableMoney.decimal(streetCommitted) }
    var awardedDecimal: Decimal { TableMoney.decimal(awarded) }

    /// Chips still behind this player, which is all they can bet.
    var remaining: Decimal {
        (stackDecimal - committedDecimal).clampedToNonNegative
    }

    var isAllIn: Bool {
        !isFolded && committedDecimal > 0 && remaining == 0
    }

    /// The most this player can put in on the street being bet.
    var streetCap: Decimal {
        streetCommittedDecimal + remaining
    }

    /// A hand a table shared before cards were dealt has no cards to turn over.
    var isDealtCards: Bool {
        cards.count == 2
    }

    /// Written by hand so a hand shared by an older build still decodes.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        seatNumber = try container.decode(Int.self, forKey: .seatNumber)
        playerKey = try container.decode(String.self, forKey: .playerKey)
        playerName = try container.decode(String.self, forKey: .playerName)
        stack = try container.decode(String.self, forKey: .stack)
        committed = try container.decode(String.self, forKey: .committed)
        streetCommitted = try container.decodeIfPresent(String.self, forKey: .streetCommitted) ?? committed
        hasActed = try container.decodeIfPresent(Bool.self, forKey: .hasActed) ?? false
        isFolded = try container.decodeIfPresent(Bool.self, forKey: .isFolded) ?? false
        cards = try container.decodeIfPresent([PlayingCard].self, forKey: .cards) ?? []
        awarded = try container.decodeIfPresent(String.self, forKey: .awarded) ?? "0"
        handSummary = try container.decodeIfPresent(String.self, forKey: .handSummary)
    }
}

/// A whole hand of poker on a shared table: the cards, the pot, whose turn it is,
/// and who ended up taking the money.
struct SharedTableHand: Codable, Equatable, Hashable {
    /// Bumped when a build deals hands the older one cannot play, so the table
    /// deals a fresh one instead of trying to carry on.
    static let currentVersion = 2

    var id: UUID
    var version: Int
    var handNumber: Int
    var revision: Int
    var dealerSeat: Int
    var ante: String
    var street: HandStreet
    /// The cards face up in the middle of the table.
    var board: [PlayingCard]
    /// What is left in the deck, so every phone deals the same next card. A
    /// shared table trusts the people sitting at it: the whole hand travels in
    /// one row, cards and all, and it is the app that keeps them face down
    /// until the showdown.
    var deck: [PlayingCard]
    var actingSeat: Int?
    var isComplete: Bool
    /// True once everyone still in the hand has turned their cards over.
    var isRevealed: Bool
    var winnerSeats: [Int]
    /// Why the hand was won, such as "Two pair, aces and eights".
    var resultSummary: String?
    var seats: [SharedTableHandSeat]

    init(
        id: UUID,
        version: Int = SharedTableHand.currentVersion,
        handNumber: Int,
        revision: Int,
        dealerSeat: Int,
        ante: String,
        street: HandStreet = .preflop,
        board: [PlayingCard] = [],
        deck: [PlayingCard] = [],
        actingSeat: Int? = nil,
        isComplete: Bool = false,
        isRevealed: Bool = false,
        winnerSeats: [Int] = [],
        resultSummary: String? = nil,
        seats: [SharedTableHandSeat]
    ) {
        self.id = id
        self.version = version
        self.handNumber = handNumber
        self.revision = revision
        self.dealerSeat = dealerSeat
        self.ante = ante
        self.street = street
        self.board = board
        self.deck = deck
        self.actingSeat = actingSeat
        self.isComplete = isComplete
        self.isRevealed = isRevealed
        self.winnerSeats = winnerSeats
        self.resultSummary = resultSummary
        self.seats = seats
    }

    var anteDecimal: Decimal { TableMoney.decimal(ante) }

    var pot: Decimal {
        seats.reduce(Decimal(0)) { $0 + $1.committedDecimal }
    }

    /// The most anyone has put in on the street being bet.
    var highestStreetCommitted: Decimal {
        seats.map(\.streetCommittedDecimal).max() ?? 0
    }

    /// What a player has to have in front of them to still be in the hand: the
    /// ante before the flop, until somebody bets more than it.
    var callTarget: Decimal {
        guard street == .preflop else { return highestStreetCommitted }
        return Swift.max(highestStreetCommitted, anteDecimal)
    }


    var contenders: [SharedTableHandSeat] {
        seats.filter { !$0.isFolded }
    }

    var isBettingComplete: Bool {
        actingSeat == nil
    }

    var winners: [SharedTableHandSeat] {
        winnerSeats.compactMap { seat(at: $0) }
    }

    /// True when this hand was dealt by a build that did not deal cards, so it
    /// cannot be played to a showdown and the table deals again.
    var needsRedeal: Bool {
        guard !isComplete else { return false }
        if version < Self.currentVersion { return true }
        return contenders.contains { !$0.isDealtCards }
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
        return Swift.min(
            (callTarget - seat.streetCommittedDecimal).clampedToNonNegative,
            seat.remaining
        )
    }

    /// Whether this player's two cards are face up for the whole table.
    func showsCards(forSeat seatNumber: Int) -> Bool {
        guard isRevealed, let seat = seat(at: seatNumber) else { return false }
        return !seat.isFolded && seat.isDealtCards
    }

    /// Written by hand so a hand shared by an older build still decodes.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        handNumber = try container.decode(Int.self, forKey: .handNumber)
        revision = try container.decode(Int.self, forKey: .revision)
        dealerSeat = try container.decode(Int.self, forKey: .dealerSeat)
        ante = try container.decode(String.self, forKey: .ante)
        street = try container.decodeIfPresent(HandStreet.self, forKey: .street) ?? .preflop
        board = try container.decodeIfPresent([PlayingCard].self, forKey: .board) ?? []
        deck = try container.decodeIfPresent([PlayingCard].self, forKey: .deck) ?? []
        actingSeat = try container.decodeIfPresent(Int.self, forKey: .actingSeat)
        isComplete = try container.decodeIfPresent(Bool.self, forKey: .isComplete) ?? false
        isRevealed = try container.decodeIfPresent(Bool.self, forKey: .isRevealed) ?? false
        winnerSeats = try container.decodeIfPresent([Int].self, forKey: .winnerSeats)
            ?? [try container.decodeIfPresent(Int.self, forKey: .winnerSeat)].compactMap { $0 }
        resultSummary = try container.decodeIfPresent(String.self, forKey: .resultSummary)
        seats = try container.decode([SharedTableHandSeat].self, forKey: .seats)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case version
        case handNumber
        case revision
        case dealerSeat
        case ante
        case street
        case board
        case deck
        case actingSeat
        case isComplete
        case isRevealed
        case winnerSeats
        /// Only read, so the one winner an older build wrote is not lost.
        case winnerSeat
        case resultSummary
        case seats
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(version, forKey: .version)
        try container.encode(handNumber, forKey: .handNumber)
        try container.encode(revision, forKey: .revision)
        try container.encode(dealerSeat, forKey: .dealerSeat)
        try container.encode(ante, forKey: .ante)
        try container.encode(street, forKey: .street)
        try container.encode(board, forKey: .board)
        try container.encode(deck, forKey: .deck)
        try container.encodeIfPresent(actingSeat, forKey: .actingSeat)
        try container.encode(isComplete, forKey: .isComplete)
        try container.encode(isRevealed, forKey: .isRevealed)
        try container.encode(winnerSeats, forKey: .winnerSeats)
        try container.encodeIfPresent(resultSummary, forKey: .resultSummary)
        try container.encode(seats, forKey: .seats)
    }
}
