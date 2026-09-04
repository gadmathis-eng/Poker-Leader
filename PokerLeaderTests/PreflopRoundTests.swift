import XCTest
@testable import PokerLeader

final class PreflopRoundTests: XCTestCase {
    private func seat(_ number: Int, key: String, amount: String, isHost: Bool = false) -> SharedTableSeat {
        SharedTableSeat(
            id: UUID(),
            seatNumber: number,
            playerName: key.capitalized,
            handle: nil,
            playerKey: key,
            amount: amount,
            isHost: isHost
        )
    }

    private func threeHandedTable() -> [SharedTableSeat] {
        [
            seat(1, key: "ana", amount: "20", isHost: true),
            seat(2, key: "ben", amount: "20"),
            seat(4, key: "cal", amount: "20")
        ]
    }

    private func dec(_ text: String) -> Decimal {
        Decimal(string: text) ?? 0
    }

    // MARK: - Order

    func testAsksTheSeatLeftOfTheDealerFirst() throws {
        let hand = try PreflopRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)

        XCTAssertEqual(hand.dealerSeat, 1)
        XCTAssertEqual(hand.actingSeat, 2)
        XCTAssertEqual(hand.pot, 0)
        XCTAssertNil(hand.winnerSeat)
    }

    func testActionOrderWrapsBackToTheDealer() {
        XCTAssertEqual(PreflopRound.actionOrder(seatNumbers: [1, 2, 4], dealerSeat: 4), [1, 2, 4])
        XCTAssertEqual(PreflopRound.actionOrder(seatNumbers: [1, 2, 4], dealerSeat: 1), [2, 4, 1])
    }

    func testSeatsWithNoMoneySitOut() throws {
        var seats = threeHandedTable()
        seats.append(seat(6, key: "dee", amount: "0"))

        let hand = try PreflopRound.start(seats: seats, dealerSeat: nil, ante: 1)

        XCTAssertEqual(hand.seats.map(\.seatNumber), [1, 2, 4])
    }

    func testNeedsTwoPlayersToDeal() {
        XCTAssertThrowsError(
            try PreflopRound.start(seats: [seat(1, key: "ana", amount: "20")], dealerSeat: nil, ante: 1)
        ) { error in
            XCTAssertEqual(error as? PreflopRoundError, .notEnoughPlayers)
        }
    }

    // MARK: - Going around the table

    func testStayingInPostsTheAnteAndPassesTheTurnOn() throws {
        let hand = try PreflopRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)
        let next = try PreflopRound.apply(move: .stayIn, playerKey: "ben", to: hand)

        XCTAssertEqual(next.seat(forPlayerKey: "ben")?.committedDecimal, 1)
        XCTAssertEqual(next.pot, 1)
        XCTAssertEqual(next.actingSeat, 4)
    }

    func testRoundEndsOnceEveryoneHasAntedUp() throws {
        var hand = try PreflopRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)
        for key in ["ben", "cal", "ana"] {
            hand = try PreflopRound.apply(move: .stayIn, playerKey: key, to: hand)
        }

        XCTAssertTrue(hand.isBettingComplete)
        XCTAssertEqual(hand.pot, 3)
        XCTAssertEqual(hand.contenders.count, 3)
        XCTAssertNil(hand.winnerSeat)
    }

    func testActingOutOfTurnIsRejected() throws {
        let hand = try PreflopRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)

        XCTAssertThrowsError(try PreflopRound.apply(move: .stayIn, playerKey: "cal", to: hand)) { error in
            XCTAssertEqual(error as? PreflopRoundError, .notYourTurn)
        }
    }

    // MARK: - Check and fold

    func testCheckingIsOnlyAllowedWithNothingToPutIn() throws {
        let anteFree = try PreflopRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 0)
        let checked = try PreflopRound.apply(move: .check, playerKey: "ben", to: anteFree)
        XCTAssertEqual(checked.seat(forPlayerKey: "ben")?.committedDecimal, 0)
        XCTAssertEqual(checked.actingSeat, 4)

        let withAnte = try PreflopRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)
        XCTAssertThrowsError(try PreflopRound.apply(move: .check, playerKey: "ben", to: withAnte)) { error in
            XCTAssertEqual(error as? PreflopRoundError, .moveNotAllowed)
        }
    }

    func testFoldingEveryoneOutHandsThePotToTheLastPlayer() throws {
        var hand = try PreflopRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)
        hand = try PreflopRound.apply(move: .stayIn, playerKey: "ben", to: hand)
        hand = try PreflopRound.apply(move: .fold, playerKey: "cal", to: hand)
        hand = try PreflopRound.apply(move: .bet, amount: 5, playerKey: "ana", to: hand)
        hand = try PreflopRound.apply(move: .fold, playerKey: "ben", to: hand)

        XCTAssertTrue(hand.isBettingComplete)
        XCTAssertEqual(hand.winnerSeat, 1)
        XCTAssertEqual(hand.pot, 6)
    }

    // MARK: - Pre-flop betting

    func testABetReopensTheActionForPlayersWhoAlreadyAnted() throws {
        var hand = try PreflopRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)
        hand = try PreflopRound.apply(move: .stayIn, playerKey: "ben", to: hand)
        hand = try PreflopRound.apply(move: .bet, amount: 4, playerKey: "cal", to: hand)

        XCTAssertEqual(hand.seat(forPlayerKey: "cal")?.committedDecimal, 4)
        XCTAssertEqual(hand.actingSeat, 1)
        XCTAssertEqual(hand.amountToCall(forPlayerKey: "ben"), 3)

        hand = try PreflopRound.apply(move: .stayIn, playerKey: "ana", to: hand)
        XCTAssertEqual(hand.actingSeat, 2, "Ben has to answer the bet even though he already anted")

        hand = try PreflopRound.apply(move: .stayIn, playerKey: "ben", to: hand)
        XCTAssertTrue(hand.isBettingComplete)
        XCTAssertEqual(hand.pot, 12)
    }

    func testABetHasToBeatWhatIsAlreadyInFrontOfTheTable() throws {
        var hand = try PreflopRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)
        hand = try PreflopRound.apply(move: .bet, amount: 4, playerKey: "ben", to: hand)

        XCTAssertThrowsError(try PreflopRound.apply(move: .bet, amount: 3, playerKey: "cal", to: hand)) { error in
            XCTAssertEqual(error as? PreflopRoundError, .moveNotAllowed)
        }
    }

    func testABetIsCappedAtTheStackAndCountsAsAllIn() throws {
        let seats = [
            seat(1, key: "ana", amount: "20", isHost: true),
            seat(2, key: "ben", amount: "3")
        ]
        var hand = try PreflopRound.start(seats: seats, dealerSeat: nil, ante: 1)
        hand = try PreflopRound.apply(move: .bet, amount: 50, playerKey: "ben", to: hand)

        let ben = try XCTUnwrap(hand.seat(forPlayerKey: "ben"))
        XCTAssertEqual(ben.committedDecimal, 3)
        XCTAssertTrue(ben.isAllIn)
        XCTAssertEqual(hand.actingSeat, 1, "The all-in still has to be called")

        hand = try PreflopRound.apply(move: .stayIn, playerKey: "ana", to: hand)
        XCTAssertTrue(hand.isBettingComplete, "An all-in player is not asked again")
        XCTAssertEqual(hand.pot, 6)
    }

    func testStayingInNeverPutsInMoreThanTheStack() throws {
        let seats = [
            seat(1, key: "ana", amount: "20", isHost: true),
            seat(2, key: "ben", amount: "2")
        ]
        var hand = try PreflopRound.start(seats: seats, dealerSeat: nil, ante: 1)
        hand = try PreflopRound.apply(move: .stayIn, playerKey: "ben", to: hand)
        hand = try PreflopRound.apply(move: .bet, amount: 9, playerKey: "ana", to: hand)
        hand = try PreflopRound.apply(move: .stayIn, playerKey: "ben", to: hand)

        XCTAssertEqual(hand.seat(forPlayerKey: "ben")?.committedDecimal, 2)
        XCTAssertTrue(hand.isBettingComplete)
    }

    // MARK: - Paying out

    func testThePotIsPushedToThePickedWinner() throws {
        var hand = try PreflopRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)
        hand = try PreflopRound.apply(move: .stayIn, playerKey: "ben", to: hand)
        hand = try PreflopRound.apply(move: .stayIn, playerKey: "cal", to: hand)
        hand = try PreflopRound.apply(move: .fold, playerKey: "ana", to: hand)

        XCTAssertTrue(hand.isBettingComplete)
        let settled = try PreflopRound.award(potTo: 4, in: hand)
        let stacks = PreflopRound.stacksAfter(settled)

        XCTAssertEqual(stacks["ana"], 20)
        XCTAssertEqual(stacks["ben"], 19)
        XCTAssertEqual(stacks["cal"], 21)
    }

    func testAFoldedPlayerCannotBeGivenThePot() throws {
        var hand = try PreflopRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)
        hand = try PreflopRound.apply(move: .fold, playerKey: "ben", to: hand)
        hand = try PreflopRound.apply(move: .stayIn, playerKey: "cal", to: hand)
        hand = try PreflopRound.apply(move: .stayIn, playerKey: "ana", to: hand)

        XCTAssertThrowsError(try PreflopRound.award(potTo: 2, in: hand)) { error in
            XCTAssertEqual(error as? PreflopRoundError, .moveNotAllowed)
        }
    }

    func testThePotCannotBeAwardedWhileTheTableIsStillBetting() throws {
        let hand = try PreflopRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)

        XCTAssertThrowsError(try PreflopRound.award(potTo: 2, in: hand)) { error in
            XCTAssertEqual(error as? PreflopRoundError, .bettingOpen)
        }
    }

    func testTheTableKeepsItsMoneyFromOneHandToTheNext() throws {
        var seats = threeHandedTable()
        var hand = try PreflopRound.start(seats: seats, dealerSeat: nil, ante: 1)
        hand = try PreflopRound.apply(move: .stayIn, playerKey: "ben", to: hand)
        hand = try PreflopRound.apply(move: .bet, amount: 4, playerKey: "cal", to: hand)
        hand = try PreflopRound.apply(move: .fold, playerKey: "ana", to: hand)
        hand = try PreflopRound.apply(move: .stayIn, playerKey: "ben", to: hand)
        hand = try PreflopRound.award(potTo: 4, in: hand)

        let stacks = PreflopRound.stacksAfter(hand)
        for index in seats.indices {
            guard let stack = stacks[seats[index].playerKey] else { continue }
            seats[index].amount = TableMoney.string(stack)
        }

        XCTAssertEqual(seats.reduce(Decimal(0)) { $0 + $1.amountDecimal }, 60)
        XCTAssertEqual(seats.first { $0.playerKey == "cal" }?.amountDecimal, 24)

        let nextHand = try PreflopRound.start(
            seats: seats,
            dealerSeat: PreflopRound.nextDealerSeat(after: hand.dealerSeat, seats: seats),
            ante: 1,
            handNumber: hand.handNumber + 1
        )

        XCTAssertEqual(nextHand.handNumber, 2)
        XCTAssertEqual(nextHand.dealerSeat, 2)
        XCTAssertEqual(nextHand.actingSeat, 4)
        XCTAssertEqual(nextHand.pot, 0)
        XCTAssertEqual(nextHand.seat(forPlayerKey: "cal")?.stackDecimal, 24)
    }

    func testTheButtonMovesOnForTheNextHand() {
        XCTAssertEqual(PreflopRound.nextDealerSeat(after: 1, seats: threeHandedTable()), 2)
        XCTAssertEqual(PreflopRound.nextDealerSeat(after: 4, seats: threeHandedTable()), 1)
    }

    // MARK: - Amounts

    func testEveryMoveBumpsTheRevisionSoTheNewestOneWins() throws {
        let hand = try PreflopRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)
        let next = try PreflopRound.apply(move: .stayIn, playerKey: "ben", to: hand)

        XCTAssertEqual(next.revision, hand.revision + 1)
        XCTAssertEqual(next.id, hand.id)
    }

    func testSuggestedBetDoublesWhatIsInFront() throws {
        var hand = try PreflopRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 2)
        XCTAssertEqual(PreflopRound.suggestedBet(in: hand, forPlayerKey: "ben"), 4)

        hand = try PreflopRound.apply(move: .bet, amount: 5, playerKey: "ben", to: hand)
        XCTAssertEqual(PreflopRound.suggestedBet(in: hand, forPlayerKey: "cal"), 10)
    }

    func testDefaultAnteIsAHundredthOfTheBuyIn() {
        XCTAssertEqual(TableAnte.defaultAmount(forBuyIn: 100), 1)
        XCTAssertEqual(TableAnte.defaultAmount(forBuyIn: 50), dec("0.5"))
        XCTAssertEqual(TableAnte.defaultAmount(forBuyIn: dec("0.2")), dec("0.01"))
        XCTAssertEqual(TableAnte.defaultAmount(forBuyIn: 0), 0)
    }
}
