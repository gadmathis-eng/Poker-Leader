import SwiftUI

enum PlayingCardSize {
    /// Fits inside a seat on the table.
    case seat
    /// The cards in the middle of the table.
    case board
    /// Your own two cards.
    case hand

    var width: CGFloat {
        switch self {
        case .seat: 18
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
        case .board: 5
        case .hand: 7
        }
    }

    var rankFont: Font {
        switch self {
        case .seat: .system(size: 10, weight: .heavy, design: .rounded)
        case .board: .system(size: 17, weight: .heavy, design: .rounded)
        case .hand: .system(size: 26, weight: .heavy, design: .rounded)
        }
    }

    var suitFont: Font {
        switch self {
        case .seat: .system(size: 7, weight: .bold)
        case .board: .system(size: 12, weight: .bold)
        case .hand: .system(size: 18, weight: .bold)
        }
    }

    var spacing: CGFloat {
        switch self {
        case .seat: 2
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
struct CardRowView: View {
    var cards: [PlayingCard] = []
    /// How many cards to show on their backs after the face-up ones.
    var faceDownCount: Int = 0
    var size: PlayingCardSize = .board

    private var backs: [Int] {
        Array(0..<max(faceDownCount, 0))
    }

    var body: some View {
        HStack(spacing: size.spacing) {
            ForEach(cards) { card in
                PlayingCardView(card: card, size: size)
            }
            ForEach(backs, id: \.self) { _ in
                FaceDownCardView(size: size)
            }
        }
    }
}

/// The three, four, or five cards in the middle of the table, with the ones
/// still to come shown as empty slots.
struct BoardCardsView: View {
    let cards: [PlayingCard]
    var size: PlayingCardSize = .board

    private var slotsToCome: [Int] {
        Array(0..<max(PokerHandEvaluator.handSize - cards.count, 0))
    }

    var body: some View {
        HStack(spacing: size.spacing) {
            ForEach(cards) { card in
                PlayingCardView(card: card, size: size)
            }
            ForEach(slotsToCome, id: \.self) { _ in
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: size.width, height: size.height)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            cards.isEmpty
                ? "No cards on the table yet"
                : "On the table: \(cards.map(\.accessibilityName).joined(separator: ", "))"
        )
    }
}