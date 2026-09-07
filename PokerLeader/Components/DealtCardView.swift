import SwiftUI

/// The dealer's spot, which every card on the felt flies out from, and the
/// coordinate space a seat measures its own distance from it in.
struct CardDealOrigin: Equatable {
    static let space = NamedCoordinateSpace.named("pokerFeltDeal")

    var point: CGPoint
}

private struct CardDealOriginKey: EnvironmentKey {
    static let defaultValue: CardDealOrigin? = nil
}

extension EnvironmentValues {
    /// Set by the table, so cards in every seat come from the same pair of
    /// hands. Away from the felt it is nil and cards drift in instead.
    var cardDealOrigin: CardDealOrigin? {
        get { self[CardDealOriginKey.self] }
        set { self[CardDealOriginKey.self] = newValue }
    }
}

/// One place in a row of cards: what lands there, and when it goes out.
struct DealtCardSlot: Identifiable {
    let id: String
    /// The face this card lands on, or nil while it is still on its back.
    var card: PlayingCard?
    var pitchDelay: Double
}

/// A card on its way to where it has been dealt: pitched from the dealer,
/// turning over in the air, and settling with a little weight where it lands.
///
/// A card with no face stays on its back, and turns over in place later when a
/// face arrives, so a hand shown down is not dealt all over again.
struct DealtCardView: View {
    var card: PlayingCard?
    var size: PlayingCardSize = .board
    /// How long after the deal starts this card goes out.
    var pitchDelay: Double = 0

    @Environment(\.cardDealOrigin) private var dealOrigin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var travel: CGSize = .zero
    @State private var isOnTheTable = false
    @State private var hasLanded = false
    @State private var isTurned = false
    @State private var showsFace = false

    var body: some View {
        sides
            .rotation3DEffect(
                .degrees(isTurned ? 180 : 0),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.35
            )
            .rotationEffect(.degrees(hasLanded ? 0 : pitchTilt))
            .scaleEffect(hasLanded ? 1 : 0.86)
            .offset(hasLanded ? .zero : approach)
            .opacity(isOnTheTable ? 1 : 0)
            .background { travelReader }
            .onPreferenceChange(CardTravelKey.self) { travel = $0 }
            .task(id: card?.id) { await deal() }
    }

    /// Two sided, with the face put on back to front, so it reads the right way
    /// round once the card has turned over.
    private var sides: some View {
        ZStack {
            FaceDownCardView(size: size)
                .opacity(showsFace ? 0 : 1)
                .accessibilityHidden(card != nil)

            if let card {
                PlayingCardView(card: card, size: size)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .opacity(showsFace ? 1 : 0)
            }
        }
    }

    /// The dealer pitches, the card turns over on its way, and the face is
    /// swapped in halfway, while the card is edge on and unreadable either way.
    ///
    /// Each part of the throw is animated on its own so the card can settle
    /// with a bounce while it turns over at a steady rate.
    private func deal() async {
        guard !reduceMotion else {
            land()
            return
        }
        guard !hasLanded else {
            await turnOverInPlace()
            return
        }

        try? await Task.sleep(for: .seconds(pitchDelay))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.12)) { isOnTheTable = true }
        withAnimation(.spring(duration: CardDealSequence.flight + 0.1, bounce: 0.3)) {
            hasLanded = true
        }
        guard card != nil else { return }
        withAnimation(turnMotion) { isTurned = true }
        await revealFace()
    }

    /// A card that has sat on its back all hand, turned over where it lies at
    /// the showdown rather than being dealt all over again.
    private func turnOverInPlace() async {
        guard card != nil, !isTurned else { return }
        try? await Task.sleep(for: .seconds(pitchDelay))
        guard !Task.isCancelled else { return }
        withAnimation(turnMotion) { isTurned = true }
        await revealFace()
    }

    private func revealFace() async {
        try? await Task.sleep(for: .seconds(CardDealSequence.turnMidpoint))
        guard !Task.isCancelled else { return }
        showsFace = true
    }

    /// No throw and no turn for anyone who would rather not watch one: the card
    /// simply fades into its place.
    private func land() {
        hasLanded = true
        isTurned = card != nil
        showsFace = card != nil
        withAnimation(.easeOut(duration: 0.18)) { isOnTheTable = true }
    }

    /// How far the card has to fly. Off the felt there is nobody to fly in
    /// from, so it drifts down from the table instead.
    private var approach: CGSize {
        if dealOrigin != nil, travel != .zero {
            return travel
        }
        return CGSize(width: 0, height: CardDealSequence.driftWhenOffTable)
    }

    /// A card leaves the dealer's hand at a slight angle, and no two cards
    /// leave at quite the same one.
    private var pitchTilt: Double {
        let seed = (card?.code ?? "back").unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(seed % 5 - 2) * 6
    }

    /// Even, rather than springy, so the halfway point is the moment the card
    /// really is edge on.
    private var turnMotion: Animation {
        .easeInOut(duration: CardDealSequence.flight)
    }

    @ViewBuilder
    private var travelReader: some View {
        if let dealOrigin {
            GeometryReader { proxy in
                let frame = proxy.frame(in: CardDealOrigin.space)
                Color.clear
                    .preference(
                        key: CardTravelKey.self,
                        value: CGSize(
                            width: dealOrigin.point.x - frame.midX,
                            height: dealOrigin.point.y - frame.midY
                        )
                    )
            }
        }
    }
}

private struct CardTravelKey: PreferenceKey {
    static let defaultValue = CGSize.zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
