import XCTest
@testable import PokerLeader

final class OpenTableSeatsPackingTests: XCTestCase {
    private func seat(_ number: Int, key: String) -> SharedTableSeat {
        SharedTableSeat(
            id: UUID(),
            seatNumber: number,
            playerName: key.capitalized,
            handle: nil,
            playerKey: key,
            amount: "20",
            isHost: key == "ana"
        )
    }

    private func players() -> [SharedTableSeat] {
        [seat(1, key: "ana"), seat(2, key: "ben")]
    }

    func testAPlainSeatListHasNoHand() throws {
        let data = try JSONEncoder().encode(players())
        let packed = try JSONDecoder().decode(OpenTablePackedSeats.self, from: data)

        XCTAssertEqual(packed.seats.map(\.playerKey), ["ana", "ben"])
        XCTAssertEqual(packed.anteAmount, "0")
        XCTAssertNil(packed.hand)
    }

    func testRoundTripKeepsTheHandAndAnte() throws {
        let hand = try HandRound.start(seats: players(), dealerSeat: nil, ante: 1)
        let packed = OpenTablePackedSeats(seats: players(), anteAmount: "1", hand: hand)

        let decoded = try JSONDecoder().decode(
            OpenTablePackedSeats.self,
            from: try JSONEncoder().encode(packed)
        )

        XCTAssertEqual(decoded.anteAmount, "1")
        XCTAssertEqual(decoded.hand, hand)
        XCTAssertEqual(decoded.seats.map(\.playerKey), ["ana", "ben"])
        XCTAssertFalse(decoded.seats.contains { OpenTableSeatsPacking.isMarker($0) })
    }

    /// The cards travel with the hand, so a friend on the packed fallback sees
    /// the same board and the same two cards in front of them.
    func testTheCardsRideAlongWithThePackedHand() throws {
        var hand = try HandRound.start(seats: players(), dealerSeat: nil, ante: 1)
        while hand.street == .preflop, let acting = hand.actingSeat {
            let key = try XCTUnwrap(hand.seat(at: acting)?.playerKey)
            hand = try HandRound.apply(move: .call, playerKey: key, to: hand)
        }

        let decoded = try JSONDecoder().decode(
            OpenTablePackedSeats.self,
            from: try JSONEncoder().encode(
                OpenTablePackedSeats(seats: players(), anteAmount: "1", hand: hand)
            )
        )

        XCTAssertEqual(hand.board.count, 3)
        XCTAssertEqual(decoded.hand?.board, hand.board)
        XCTAssertEqual(decoded.hand?.seats.map(\.cards), hand.seats.map(\.cards))
        XCTAssertEqual(decoded.hand?.deck, hand.deck)
    }

    func testClearingTheHandEncodesAnExplicitNull() throws {
        let packed = OpenTablePackedSeats(seats: players(), anteAmount: "0", hand: nil)
        let data = try JSONEncoder().encode(packed)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let marker = try XCTUnwrap(json.last)

        XCTAssertEqual(marker["playerKey"] as? String, OpenTableSeatsPacking.markerPlayerKey)
        XCTAssertTrue(marker["hand"] is NSNull)
        XCTAssertNil(try JSONDecoder().decode(OpenTablePackedSeats.self, from: data).hand)
    }

    func testPlayersDropsTheMarkerAndSeatZero() {
        let marker = SharedTableSeat(
            id: OpenTableSeatsPacking.markerId,
            seatNumber: 0,
            playerName: "",
            handle: nil,
            playerKey: OpenTableSeatsPacking.markerPlayerKey,
            amount: "0",
            isHost: false
        )

        XCTAssertEqual(
            OpenTableSeatsPacking.players(in: players() + [marker]).map(\.playerKey),
            ["ana", "ben"]
        )
    }
}
