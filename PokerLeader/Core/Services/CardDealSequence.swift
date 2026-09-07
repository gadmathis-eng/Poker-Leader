import CoreGraphics
import Foundation

/// The rhythm a dealer keeps: one card at a time, round the table, twice over,
/// and the board laid out a street at a time.
///
/// Kept out of the views so the order the cards go out in, and the beat between
/// them, can be read and tested without running an animation.
enum CardDealSequence {
    /// The three cards of the flop land together. The turn and the river each
    /// add one to what is already out.
    static let flopCount = 3

    /// A beat before the first card, long enough for a card that has only just
    /// been laid out to know where it is flying in from.
    static let lead: Double = 0.06

    /// The gap between two seats being pitched a card.
    static let seatGap: Double = 0.05

    /// The gap between the first card round the table and the second.
    static let roundGap: Double = 0.16

    /// How long a card is in the air, which is also how long it takes to turn
    /// over.
    static let flight: Double = 0.36

    /// The moment a card is edge on and neither side of it can be read: when to
    /// swap its back for its face.
    static var turnMidpoint: Double { flight / 2 }

    /// How far a card slides when it is not on the felt, and so has no dealer
    /// to fly in from. Negative, because the table sits above your own hand.
    static let driftWhenOffTable: CGFloat = -26

    /// When a card goes out, counted from the moment the deal starts.
    ///
    /// - Parameters:
    ///   - cardIndex: Which time round the table this card is, counting from 0.
    ///   - seatPosition: Where the seat sits in the dealer's order, from 0.
    static func pitch(cardIndex: Int, seatPosition: Int = 0) -> Double {
        lead
            + Double(max(seatPosition, 0)) * seatGap
            + Double(max(cardIndex, 0)) * roundGap
    }

    /// The first board card of the street being dealt, so the cards already
    /// face up on the felt do not wait their turn all over again.
    static func firstNewBoardCard(inBoardOf count: Int) -> Int {
        count <= flopCount ? 0 : count - 1
    }

    /// Where each seat sits in the dealer's order, keyed by seat number.
    static func seatPositions(inDealerOrder order: [Int]) -> [Int: Int] {
        var positions: [Int: Int] = [:]
        for (position, seatNumber) in order.enumerated() {
            positions[seatNumber] = position
        }
        return positions
    }
}
