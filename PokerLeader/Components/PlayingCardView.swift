import SwiftUI

enum PlayingCardSize {
    /// Fits inside a seat on the table.
    case seat
    /// The five community cards on the felt, with the seats crowding in around them.
    case table
    /// A hand laid out in a list row, like the showdown.
    case board
    /// Your own two cards.
    case hand

    var width: CGFloat {
        switch self {
        case .seat: 18
        case .table: 28
        case .board: 34
        case .hand: 54
        }
    }

    var height: CGFloat {
        width * 1.42
    }

    var cornerRadius: CGFloat {
        switch self {
        case .seat: 3
        case .table: 4
        case .board: 5
        case .hand: 7
        }
    }

    var rankFont: Font {
        switch self {
        case .seat: .system(size: 10, weight: .heavy, design: .rounded)
        case .table: .system(size: 14, weight: .heavy, design: .rounded)
        case .board: .system(size: 17, weight: .heavy, design: .rounded)
        case .hand: .system(size: 26, weight: .heavy, design: .rounded)
        }
    }

    var suitFont: Font {
        switch self {
        case .seat: .system(size: 7, weight: .bold)
        case .table: .system(size: 10, weight: .bold)
        case .board: .system(size: 12, weight: .bold)
        case .hand: .system(size: 18, weight: .bold)
        }
    }

    var spacing: CGFloat {
        switch self {
        case .seat: 2
        case .table: 4
        case .board: 5
        case .hand: 7
        }
    }
}

struct PlayingCardView: View {
    let card: PlayingCard
    var size: PlayingCardSize = .board

    private var ink: Color {
        card.isRed ? Color(red: 0.83, green: 0.16, blue: 0.18) : Color(red: 0.11, green: 0.12, blue: 0.15)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(card.rankSymbol)
                .font(size.rankFont)
            Text(card.suit.symbol)
                .font(size.suitFont)
        }
        .foregroundStyle(ink)
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .stroke(Color.black.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
        .accessibilityLabel(card.accessibilityName)
    }
}

struct FaceDownCardView: View {
    var size: PlayingCardSize = .board

    var body: some View {
        RoundedRectangle(cornerRadius: size.cornerRadius)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.16, green: 0.29, blue: 0.55), Color(red: 0.09, green: 0.16, blue: 0.34)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size.width, height: size.height)
            .overlay(
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
                    .padding(1.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
            .accessibilityLabel("Face down card")
    }
}

/// A row of cards: face up where they are known, face down where they are not.
/// Each one is dealt in, in turn, and a back turns over where it lies once its
/// face is known.
struct CardRowView: View {
    var cards: [PlayingCard] = []
    /// How many cards to show on their backs after the face-up ones.
    var faceDownCount: Int = 0
    var size: PlayingCardSize = .board
    /// Changes when a fresh set of cards is dealt, so they go out again.
    var dealID: String = ""
    /// Where this player sits in the dealer's order, so the seats are dealt to
    /// one after another rather than all at once.
    var dealPosition: Int = 0

    private var slots: [DealtCardSlot] {
        let total = cards.count + max(faceDownCount, 0)
        return (0..<total).map { index in
            DealtCardSlot(
                id: "\(dealID)/\(index)",
                card: index < cards.count ? cards[index] : nil,
                pitchDelay: CardDealSequence.pitch(cardIndex: index, seatPosition: dealPosition)
            )
        }
    }

    var body: some View {
        HStack(spacing: size.spacing) {
            ForEach(slots) { slot in
                DealtCardView(card: slot.card, size: size, pitchDelay: slot.pitchDelay)
            }
        }
    }
}

/// The three, four, or five cards in the middle of the table, with the ones
/// still to come shown as empty slots. A street is laid out card by card into
/// the slots waiting for it.
struct BoardCardsView: View {
    let cards: [PlayingCard]
    var size: PlayingCardSize = .board
    /// Changes when a new hand is dealt, so the board is laid out again.
    var dealID: String = ""

    private var slots: [DealtCardSlot] {
        let firstNew = CardDealSequence.firstNewBoardCard(inBoardOf: cards.count)
        return cards.enumerated().map { index, card in
            DealtCardSlot(
                id: "\(dealID)/\(index)",
                card: card,
                pitchDelay: CardDealSequence.pitch(cardIndex: max(index - firstNew, 0))
            )
        }
    }

    private var slotsToCome: [Int] {
        Array(0..<max(PokerHandEvaluator.handSize - cards.count, 0))
    }

    var body: some View {
        HStack(spacing: size.spacing) {
            ForEach(slots) { slot in
                DealtCardView(card: slot.card, size: size, pitchDelay: slot.pitchDelay)
                    .background { emptySlot }
            }
            ForEach(slotsToCome, id: \.self) { _ in
                emptySlot
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            cards.isEmpty
                ? "No cards on the table yet"
                : "On the table: \(cards.map(\.accessibilityName).joined(separator: ", "))"
        )
    }

    /// Where a card is going to land, left marked until it gets there. Drawn
    /// inside the slot, so a card that has landed covers it over.
    private var emptySlot: some View {
        RoundedRectangle(cornerRadius: size.cornerRadius)
            .strokeBorder(
                AppTheme.muted.opacity(0.4),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
            .frame(width: size.width, height: size.height)
    }
}