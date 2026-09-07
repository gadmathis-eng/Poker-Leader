import XCTest
@testable import PokerLeader

final class CardDealSequenceTests: XCTestCase {
    func testTheFirstCardWaitsOnlyForTheLead() {
        XCTAssertEqual(
            CardDealSequence.pitch(cardIndex: 0, seatPosition: 0),
            CardDealSequence.lead,
            accuracy: 0.0001
        )
    }

    func testSeatsAreDealtToOneAfterAnother() {
        let first = CardDealSequence.pitch(cardIndex: 0, seatPosition: 0)
        let second = CardDealSequence.pitch(cardIndex: 0, seatPosition: 1)
        let third = CardDealSequence.pitch(cardIndex: 0, seatPosition: 2)

        XCTAssertEqual(second - first, CardDealSequence.seatGap, accuracy: 0.0001)
        XCTAssertEqual(third - second, CardDealSequence.seatGap, accuracy: 0.0001)
    }

    func testTheSecondCardGoesRoundTheTableAfterTheFirst() {
        let firstRound = CardDealSequence.pitch(cardIndex: 0, seatPosition: 0, seatsInDeal: 4)
        let secondRound = CardDealSequence.pitch(cardIndex: 1, seatPosition: 0, seatsInDeal: 4)

        XCTAssertEqual(
            secondRound - firstRound,
            CardDealSequence.roundGap(seatsInDeal: 4),
            accuracy: 0.0001
        )
        XCTAssertGreaterThan(CardDealSequence.roundGap(seatsInDeal: 4), CardDealSequence.seatGap)
    }

    /// The whole table gets its first card before anyone gets a second, which
    /// is the one thing that would give the deal away as an animation.
    func testNobodyGetsASecondCardBeforeTheTableHasHadItsFirst() {
        for seats in 2...8 {
            let lastOfTheFirstRound = CardDealSequence.pitch(
                cardIndex: 0,
                seatPosition: seats - 1,
                seatsInDeal: seats
            )
            let firstOfTheSecondRound = CardDealSequence.pitch(
                cardIndex: 1,
                seatPosition: 0,
                seatsInDeal: seats
            )

            XCTAssertLessThan(
                lastOfTheFirstRound,
                firstOfTheSecondRound,
                "A table of \(seats) deals its second card too early"
            )
        }
    }

    func testABusyTableTakesLongerToGoRound() {
        XCTAssertGreaterThan(
            CardDealSequence.roundGap(seatsInDeal: 8),
            CardDealSequence.roundGap(seatsInDeal: 2)
        )
    }

    func testAQuietTableStillLeavesTheShortestGapWorthSeeing() {
        XCTAssertEqual(
            CardDealSequence.roundGap(seatsInDeal: 1),
            CardDealSequence.minimumRoundGap,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CardDealSequence.roundGap(seatsInDeal: 0),
            CardDealSequence.minimumRoundGap,
            accuracy: 0.0001
        )
    }

    func testNegativePositionsDoNotPullCardsForward() {
        XCTAssertEqual(
            CardDealSequence.pitch(cardIndex: -3, seatPosition: -2, seatsInDeal: -1),
            CardDealSequence.lead,
            accuracy: 0.0001
        )
    }

    func testAHeadsUpDealIsOverQuickly() {
        let last = CardDealSequence.pitch(cardIndex: 1, seatPosition: 1, seatsInDeal: 2)

        XCTAssertLessThan(last + CardDealSequence.flight, 1)
    }

    func testAFullTableIsStillDealtInUnderTwoSeconds() {
        let last = CardDealSequence.pitch(cardIndex: 1, seatPosition: 7, seatsInDeal: 8)

        XCTAssertLessThan(last + CardDealSequence.flight, 2)
    }

    func testACardTurnsOverHalfwayThroughItsFlight() {
        XCTAssertEqual(CardDealSequence.turnMidpoint, CardDealSequence.flight / 2, accuracy: 0.0001)
        XCTAssertGreaterThan(CardDealSequence.turnMidpoint, 0)
        XCTAssertLessThan(CardDealSequence.turnMidpoint, CardDealSequence.flight)
    }

    func testTheWholeFlopIsDealtAsNewCards() {
        XCTAssertEqual(CardDealSequence.firstNewBoardCard(inBoardOf: 3), 0)

        let delays = (0..<3).map { CardDealSequence.pitch(cardIndex: $0) }
        XCTAssertEqual(delays, delays.sorted())
        XCTAssertGreaterThan(delays[2], delays[0])
    }

    func testTheTurnAndTheRiverOnlyDealTheirOwnCard() {
        XCTAssertEqual(CardDealSequence.firstNewBoardCard(inBoardOf: 4), 3)
        XCTAssertEqual(CardDealSequence.firstNewBoardCard(inBoardOf: 5), 4)
    }

    func testCardsAlreadyOnTheBoardDoNotWaitTheirTurnAgain() {
        let count = 4
        let firstNew = CardDealSequence.firstNewBoardCard(inBoardOf: count)
        let delays = (0..<count).map {
            CardDealSequence.pitch(cardIndex: max($0 - firstNew, 0))
        }

        XCTAssertEqual(delays[0], CardDealSequence.lead, accuracy: 0.0001)
        XCTAssertEqual(delays[3], CardDealSequence.lead, accuracy: 0.0001)
    }

    func testAnEmptyBoardStartsAtTheFirstCard() {
        XCTAssertEqual(CardDealSequence.firstNewBoardCard(inBoardOf: 0), 0)
    }

    func testSeatPositionsFollowTheDealersOrder() {
        let order = HandRound.actionOrder(seatNumbers: [1, 3, 6], dealerSeat: 3)
        let positions = CardDealSequence.seatPositions(inDealerOrder: order)

        XCTAssertEqual(order, [6, 1, 3])
        XCTAssertEqual(positions[6], 0)
        XCTAssertEqual(positions[1], 1)
        XCTAssertEqual(positions[3], 2)
    }

    func testTheDealerIsDealtToLast() {
        let seats = [2, 4, 5, 8]
        let order = HandRound.actionOrder(seatNumbers: seats, dealerSeat: 5)
        let positions = CardDealSequence.seatPositions(inDealerOrder: order)

        XCTAssertEqual(positions[5], seats.count - 1)
        XCTAssertEqual(positions.count, seats.count)
    }

    func testSeatsWithNoHandHaveNoPosition() {
        let positions = CardDealSequence.seatPositions(inDealerOrder: [])

        XCTAssertNil(positions[1])
    }

    func testACardWithNobodyAheadOfItGoesOutStraightAway() {
        XCTAssertEqual(
            CardDealTurn.firstInLine.pitchDelay(forCardAt: 0),
            CardDealSequence.lead,
            accuracy: 0.0001
        )
    }

    func testATurnDealsItsOwnSeatInOrder() {
        let turn = CardDealTurn(dealID: "hand", position: 2, seatCount: 5)

        XCTAssertEqual(
            turn.pitchDelay(forCardAt: 0),
            CardDealSequence.pitch(cardIndex: 0, seatPosition: 2, seatsInDeal: 5),
            accuracy: 0.0001
        )
        XCTAssertGreaterThan(turn.pitchDelay(forCardAt: 1), turn.pitchDelay(forCardAt: 0))
    }
}
