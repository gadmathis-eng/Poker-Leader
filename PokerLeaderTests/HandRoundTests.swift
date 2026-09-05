import XCTest
@testable import PokerLeader

final class HandRoundTests: XCTestCase {
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

    private func headsUpTable() -> [SharedTableSeat] {
        [
            seat(1, key: "ana", amount: "20", isHost: true),
            seat(2, key: "ben", amount: "20")
        ]
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

    /// A deck whose first cards are dealt in a known order, then whatever is left.
    private func stacked(_ codes: [String]) -> [PlayingCard] {
        let known = CardDeck.deck(codes)
        XCTAssertEqual(known.count, codes.count, "\(codes) has a card code in it that is not a card")
        return known + CardDeck.ordered.filter { !known.contains($0) }
    }

    private func moneyOnTheTable(_ hand: SharedTableHand) -> Decimal {
        HandRound.stacksAfter(hand).values.reduce(0, +)
    }

    // MARK: - Dealing

    func testEveryoneIsDealtTwoCardsAndAskedLeftOfTheDealer() throws {
        let hand = try HandRound.start(
            seats: threeHandedTable(),
            dealerSeat: nil,
            ante: 1,
            deck: stacked(["2c", "3c", "4c", "5c", "6c", "7c"])
        )

        XCTAssertEqual(hand.dealerSeat, 1)
        XCTAssertEqual(hand.actingSeat, 2)
        XCTAssertEqual(hand.street, .preflop)
        XCTAssertTrue(hand.board.isEmpty)
        XCTAssertEqual(hand.pot, 0)
        XCTAssertTrue(hand.winnerSeats.isEmpty)
        XCTAssertTrue(hand.seats.allSatisfy { $0.cards.count == HandRound.holeCardCount })
        XCTAssertEqual(hand.deck.count, CardDeck.cardCount - 6)
    }

    func testCardsGoRoundTheTableOneAtATime() throws {
        let hand = try HandRound.start(
            seats: threeHandedTable(),
            dealerSeat: nil,
            ante: 1,
            deck: stacked(["2c", "3c", "4c", "5c", "6c", "7c"])
        )

        XCTAssertEqual(hand.seat(at: 2)?.cards.map(\.code), ["2c", "5c"])
        XCTAssertEqual(hand.seat(at: 4)?.cards.map(\.code), ["3c", "6c"])
        XCTAssertEqual(hand.seat(at: 1)?.cards.map(\.code), ["4c", "7c"])
    }

    func testNobodySeesAnyoneElsesCardsUntilTheShowdown() throws {
        let hand = try HandRound.start(seats: headsUpTable(), dealerSeat: nil, ante: 1)

        XCTAssertFalse(hand.isRevealed)
        XCTAssertFalse(hand.showsCards(forSeat: 1))
        XCTAssertFalse(hand.showsCards(forSeat: 2))
    }

    func testSeatsWithNoMoneySitOut() throws {
        var seats = threeHandedTable()
        seats.append(seat(6, key: "dee", amount: "0"))

        let hand = try HandRound.start(seats: seats, dealerSeat: nil, ante: 1)

        XCTAssertEqual(hand.seats.map(\.seatNumber), [1, 2, 4])
    }

    func testNeedsTwoPlayersToDeal() {
        XCTAssertThrowsError(
            try HandRound.start(seats: [seat(1, key: "ana", amount: "20")], dealerSeat: nil, ante: 1)
        ) { error in
            XCTAssertEqual(error as? HandRoundError, .notEnoughPlayers)
        }
    }

    func testActionOrderWrapsBackToTheDealer() {
        XCTAssertEqual(HandRound.actionOrder(seatNumbers: [1, 2, 4], dealerSeat: 4), [1, 2, 4])
        XCTAssertEqual(HandRound.actionOrder(seatNumbers: [1, 2, 4], dealerSeat: 1), [2, 4, 1])
    }

    // MARK: - The ante round

    func testStayingInPostsTheAnteAndPassesTheTurnOn() throws {
        let hand = try HandRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)
        let next = try HandRound.apply(move: .call, playerKey: "ben", to: hand)

        XCTAssertEqual(next.seat(forPlayerKey: "ben")?.committedDecimal, 1)
        XCTAssertEqual(next.pot, 1)
        XCTAssertEqual(next.actingSeat, 4)
    }

    func testActingOutOfTurnIsRejected() throws {
        let hand = try HandRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)

        XCTAssertThrowsError(try HandRound.apply(move: .call, playerKey: "cal", to: hand)) { error in
            XCTAssertEqual(error as? HandRoundError, .notYourTurn)
        }
    }

    func testCheckingIsNotAllowedWhileTheAnteIsOwed() throws {
        let hand = try HandRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)

        XCTAssertThrowsError(try HandRound.apply(move: .check, playerKey: "ben", to: hand)) { error in
            XCTAssertEqual(error as? HandRoundError, .moveNotAllowed)
        }
    }

    func testABetReopensTheActionForPlayersWhoAlreadyAnted() throws {
        var hand = try HandRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)
        hand = try HandRound.apply(move: .call, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .bet, amount: 4, playerKey: "cal", to: hand)

        XCTAssertEqual(hand.seat(forPlayerKey: "cal")?.committedDecimal, 4)
        XCTAssertEqual(hand.actingSeat, 1)
        XCTAssertEqual(hand.amountToCall(forPlayerKey: "ben"), 3)

        hand = try HandRound.apply(move: .call, playerKey: "ana", to: hand)
        XCTAssertEqual(hand.actingSeat, 2, "Ben has to answer the bet even though he already anted")

        hand = try HandRound.apply(move: .call, playerKey: "ben", to: hand)
        XCTAssertEqual(hand.street, .flop, "The ante round is done, so the flop comes out")
        XCTAssertEqual(hand.pot, 12)
    }

    func testABetHasToBeatWhatIsAlreadyInFrontOfTheTable() throws {
        var hand = try HandRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)
        hand = try HandRound.apply(move: .bet, amount: 4, playerKey: "ben", to: hand)

        XCTAssertThrowsError(try HandRound.apply(move: .bet, amount: 3, playerKey: "cal", to: hand)) { error in
            XCTAssertEqual(error as? HandRoundError, .betTooSmall)
        }
    }

    // MARK: - Street by street

    func testTheTableIsAskedAgainOnEveryStreet() throws {
        var hand = try HandRound.start(
            seats: headsUpTable(),
            dealerSeat: nil,
            ante: 1,
            deck: stacked(["2c", "3c", "4c", "5c", "6h", "7h", "8h", "9s", "Td"])
        )

        hand = try HandRound.apply(move: .call, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .call, playerKey: "ana", to: hand)

        XCTAssertEqual(hand.street, .flop)
        XCTAssertEqual(hand.board.map(\.code), ["6h", "7h", "8h"])
        XCTAssertEqual(hand.actingSeat, 2, "The flop starts left of the dealer again")
        XCTAssertEqual(hand.amountToCall(forPlayerKey: "ben"), 0, "Nothing is owed until somebody bets")

        hand = try HandRound.apply(move: .check, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .check, playerKey: "ana", to: hand)

        XCTAssertEqual(hand.street, .turn)
        XCTAssertEqual(hand.board.map(\.code), ["6h", "7h", "8h", "9s"])

        hand = try HandRound.apply(move: .check, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .check, playerKey: "ana", to: hand)

        XCTAssertEqual(hand.street, .river)
        XCTAssertEqual(hand.board.map(\.code), ["6h", "7h", "8h", "9s", "Td"])

        hand = try HandRound.apply(move: .check, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .check, playerKey: "ana", to: hand)

        XCTAssertEqual(hand.street, .showdown)
        XCTAssertTrue(hand.isComplete)
        XCTAssertTrue(hand.isRevealed)
    }

    func testABetOnTheFlopHasToBeCalledOrFolded() throws {
        var hand = try HandRound.start(seats: headsUpTable(), dealerSeat: nil, ante: 1)
        hand = try HandRound.apply(move: .call, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .call, playerKey: "ana", to: hand)
        hand = try HandRound.apply(move: .bet, amount: 4, playerKey: "ben", to: hand)

        XCTAssertEqual(hand.street, .flop)
        XCTAssertEqual(hand.amountToCall(forPlayerKey: "ana"), 4)
        XCTAssertEqual(hand.seat(forPlayerKey: "ben")?.committedDecimal, 5, "The ante plus the bet")
        XCTAssertEqual(hand.seat(forPlayerKey: "ben")?.streetCommittedDecimal, 4)

        hand = try HandRound.apply(move: .call, playerKey: "ana", to: hand)

        XCTAssertEqual(hand.street, .turn)
        XCTAssertEqual(hand.pot, 10)
        XCTAssertTrue(hand.seats.allSatisfy { $0.streetCommittedDecimal == 0 }, "Each street starts fresh")
    }

    func testRaisingOnTheRiverIsSizedForThatStreet() throws {
        var hand = try HandRound.start(seats: headsUpTable(), dealerSeat: nil, ante: 1)
        for key in ["ben", "ana"] {
            hand = try HandRound.apply(move: .call, playerKey: key, to: hand)
        }
        for _ in 0..<3 {
            hand = try HandRound.apply(move: .check, playerKey: "ben", to: hand)
            hand = try HandRound.apply(move: .check, playerKey: "ana", to: hand)
        }

        XCTAssertEqual(hand.street, .showdown)
    }

    // MARK: - Showdown

    func testTheBestHandTakesThePotAndBothHandsAreTurnedOver() throws {
        var hand = try HandRound.start(
            seats: headsUpTable(),
            dealerSeat: nil,
            ante: 1,
            deck: stacked(["2c", "Ah", "7d", "Kh", "3h", "9h", "Jh", "4s", "5d"])
        )

        hand = try HandRound.apply(move: .call, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .call, playerKey: "ana", to: hand)
        for _ in 0..<3 {
            hand = try HandRound.apply(move: .check, playerKey: "ben", to: hand)
            hand = try HandRound.apply(move: .check, playerKey: "ana", to: hand)
        }

        XCTAssertEqual(hand.seat(forPlayerKey: "ana")?.cards.map(\.code), ["Ah", "Kh"])
        XCTAssertEqual(hand.seat(forPlayerKey: "ben")?.cards.map(\.code), ["2c", "7d"])
        XCTAssertEqual(hand.winnerSeats, [1])
        XCTAssertEqual(hand.resultSummary, "Flush, ace high")
        XCTAssertEqual(hand.seat(forPlayerKey: "ana")?.handSummary, "Flush, ace high")
        XCTAssertEqual(hand.seat(forPlayerKey: "ben")?.handSummary, "Jack high")
        XCTAssertTrue(hand.showsCards(forSeat: 1))
        XCTAssertTrue(hand.showsCards(forSeat: 2))

        XCTAssertEqual(hand.seat(forPlayerKey: "ana")?.awardedDecimal, 2)
        XCTAssertEqual(HandRound.stacksAfter(hand)["ana"], 21)
        XCTAssertEqual(HandRound.stacksAfter(hand)["ben"], 19)
    }

    func testTwoOfTheSameHandSplitThePot() throws {
        var hand = try HandRound.start(
            seats: headsUpTable(),
            dealerSeat: nil,
            ante: 1,
            deck: stacked(["2c", "3c", "4d", "5d", "As", "Ks", "Qs", "Js", "Ts"])
        )

        hand = try HandRound.apply(move: .call, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .call, playerKey: "ana", to: hand)
        for _ in 0..<3 {
            hand = try HandRound.apply(move: .check, playerKey: "ben", to: hand)
            hand = try HandRound.apply(move: .check, playerKey: "ana", to: hand)
        }

        XCTAssertEqual(hand.winnerSeats, [1, 2])
        XCTAssertEqual(hand.resultSummary, "Royal flush")
        XCTAssertEqual(HandRound.stacksAfter(hand)["ana"], 20)
        XCTAssertEqual(HandRound.stacksAfter(hand)["ben"], 20)
    }

    func testAnOddPennyGoesToTheFirstPlayerLeftOfTheDealer() throws {
        var hand = try HandRound.start(
            seats: headsUpTable(),
            dealerSeat: nil,
            ante: dec("0.05"),
            deck: stacked(["2c", "3c", "4d", "5d", "As", "Ks", "Qs", "Js", "Ts"])
        )

        hand = try HandRound.apply(move: .call, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .call, playerKey: "ana", to: hand)
        for _ in 0..<3 {
            hand = try HandRound.apply(move: .check, playerKey: "ben", to: hand)
            hand = try HandRound.apply(move: .check, playerKey: "ana", to: hand)
        }

        XCTAssertEqual(hand.pot, dec("0.1"))
        XCTAssertEqual(hand.seat(forPlayerKey: "ben")?.awardedDecimal, dec("0.05"))
        XCTAssertEqual(hand.seat(forPlayerKey: "ana")?.awardedDecimal, dec("0.05"))
        XCTAssertEqual(moneyOnTheTable(hand), 40, "Splitting a pot cannot lose a penny")
    }

    func testAShortStackOnlyWinsWhatItCovered() throws {
        var seats = threeHandedTable()
        seats[2] = seat(4, key: "cal", amount: "5")

        var hand = try HandRound.start(
            seats: seats,
            dealerSeat: nil,
            ante: 1,
            deck: stacked(["2c", "9h", "Qs", "3d", "Qc", "Qd", "Jh", "Th", "2s", "7c", "8d"])
        )

        hand = try HandRound.apply(move: .bet, amount: 10, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .call, playerKey: "cal", to: hand)
        hand = try HandRound.apply(move: .call, playerKey: "ana", to: hand)

        XCTAssertEqual(hand.seat(forPlayerKey: "cal")?.committedDecimal, 5, "Cal is all in for what he had")
        XCTAssertEqual(hand.street, .flop)

        for _ in 0..<3 {
            hand = try HandRound.apply(move: .check, playerKey: "ben", to: hand)
            hand = try HandRound.apply(move: .check, playerKey: "ana", to: hand)
        }

        XCTAssertEqual(hand.street, .showdown)
        XCTAssertEqual(hand.seat(forPlayerKey: "cal")?.handSummary, "Straight, queen high")
        XCTAssertEqual(hand.seat(forPlayerKey: "ana")?.handSummary, "Pair of queens")
        XCTAssertEqual(hand.seat(forPlayerKey: "ben")?.handSummary, "Pair of twos")

        let stacks = HandRound.stacksAfter(hand)
        XCTAssertEqual(stacks["cal"], 15, "The main pot only, since Cal could not cover the rest")
        XCTAssertEqual(stacks["ana"], 20, "Ana takes the side pot back off Ben")
        XCTAssertEqual(stacks["ben"], 10)
        XCTAssertEqual(moneyOnTheTable(hand), 45)
    }

    func testAnAllInRunsTheBoardOutWithoutAskingAnybody() throws {
        var seats = headsUpTable()
        seats[0] = seat(1, key: "ana", amount: "5", isHost: true)
        seats[1] = seat(2, key: "ben", amount: "5")

        var hand = try HandRound.start(seats: seats, dealerSeat: nil, ante: 1)
        hand = try HandRound.apply(move: .bet, amount: 5, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .call, playerKey: "ana", to: hand)

        XCTAssertEqual(hand.street, .showdown)
        XCTAssertEqual(hand.board.count, 5)
        XCTAssertTrue(hand.isComplete)
        XCTAssertTrue(hand.isRevealed)
        XCTAssertNil(hand.actingSeat)
        XCTAssertEqual(moneyOnTheTable(hand), 10)
    }

    // MARK: - Folding

    func testFoldingEveryoneOutHandsThePotOverWithNoCardsShown() throws {
        var hand = try HandRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)
        hand = try HandRound.apply(move: .call, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .fold, playerKey: "cal", to: hand)
        hand = try HandRound.apply(move: .bet, amount: 5, playerKey: "ana", to: hand)
        hand = try HandRound.apply(move: .fold, playerKey: "ben", to: hand)

        XCTAssertTrue(hand.isComplete)
        XCTAssertFalse(hand.isRevealed, "Nobody has to show when everyone folds")
        XCTAssertEqual(hand.winnerSeats, [1])
        XCTAssertEqual(hand.resultSummary, "Everyone else folded.")
        XCTAssertEqual(hand.pot, 6)
        XCTAssertEqual(HandRound.stacksAfter(hand)["ana"], 21, "Her own bet back, plus Ben's ante")
        XCTAssertEqual(moneyOnTheTable(hand), 60)
    }

    func testFoldingOnTheRiverEndsTheHandThere() throws {
        var hand = try HandRound.start(seats: headsUpTable(), dealerSeat: nil, ante: 1)
        hand = try HandRound.apply(move: .call, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .call, playerKey: "ana", to: hand)
        for _ in 0..<2 {
            hand = try HandRound.apply(move: .check, playerKey: "ben", to: hand)
            hand = try HandRound.apply(move: .check, playerKey: "ana", to: hand)
        }

        XCTAssertEqual(hand.street, .river)

        hand = try HandRound.apply(move: .bet, amount: 6, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .fold, playerKey: "ana", to: hand)

        XCTAssertEqual(hand.winnerSeats, [2])
        XCTAssertEqual(hand.board.count, 5)
        XCTAssertEqual(HandRound.stacksAfter(hand)["ben"], 21)
        XCTAssertEqual(moneyOnTheTable(hand), 40)
    }

    // MARK: - Walking away mid-hand

    func testLeavingOnYourTurnPassesTheTurnOn() throws {
        var hand = try HandRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)
        hand = try HandRound.apply(move: .call, playerKey: "ben", to: hand)

        let after = try XCTUnwrap(HandRound.withdraw(playerKey: "cal", from: hand))

        XCTAssertEqual(after.seat(forPlayerKey: "cal")?.isFolded, true)
        XCTAssertEqual(after.actingSeat, 1)
        XCTAssertEqual(after.revision, hand.revision + 1)
    }

    func testLeavingOutOfTurnDoesNotSkipWhoeverIsBeingAsked() throws {
        let hand = try HandRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)

        let after = try XCTUnwrap(HandRound.withdraw(playerKey: "cal", from: hand))

        XCTAssertEqual(after.actingSeat, 2, "Ben was being asked and still is")
        XCTAssertEqual(after.contenders.count, 2)
    }

    func testLeavingKeepsWhatYouAlreadyPutInAndCanEndTheHand() throws {
        var hand = try HandRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)
        hand = try HandRound.apply(move: .call, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .fold, playerKey: "cal", to: hand)

        let after = try XCTUnwrap(HandRound.withdraw(playerKey: "ben", from: hand))

        XCTAssertEqual(after.pot, 1, "Ben's ante stays in the pot")
        XCTAssertTrue(after.isComplete)
        XCTAssertEqual(after.winnerSeats, [1], "Ana is the last one left")
        XCTAssertEqual(HandRound.stacksAfter(after)["ana"], 21)
        XCTAssertEqual(moneyOnTheTable(after), 60)
    }

    func testLeavingWhenYouWereNotInTheHandChangesNothing() throws {
        var hand = try HandRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)
        XCTAssertNil(HandRound.withdraw(playerKey: "dee", from: hand))

        hand = try HandRound.apply(move: .fold, playerKey: "ben", to: hand)
        XCTAssertNil(HandRound.withdraw(playerKey: "ben", from: hand), "Already folded")
    }

    func testAFinishedHandIsLeftAlone() throws {
        var hand = try HandRound.start(seats: headsUpTable(), dealerSeat: nil, ante: 1)
        hand = try HandRound.apply(move: .fold, playerKey: "ben", to: hand)

        XCTAssertTrue(hand.isComplete)
        XCTAssertNil(HandRound.withdraw(playerKey: "ana", from: hand))
        XCTAssertThrowsError(try HandRound.apply(move: .call, playerKey: "ana", to: hand)) { error in
            XCTAssertEqual(error as? HandRoundError, .bettingClosed)
        }
    }

    // MARK: - One hand to the next

    func testTheTableKeepsItsMoneyFromOneHandToTheNext() throws {
        var seats = threeHandedTable()
        var hand = try HandRound.start(seats: seats, dealerSeat: nil, ante: 1)
        hand = try HandRound.apply(move: .call, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .bet, amount: 4, playerKey: "cal", to: hand)
        hand = try HandRound.apply(move: .fold, playerKey: "ana", to: hand)
        hand = try HandRound.apply(move: .fold, playerKey: "ben", to: hand)

        let stacks = HandRound.stacksAfter(hand)
        for index in seats.indices {
            guard let stack = stacks[seats[index].playerKey] else { continue }
            seats[index].amount = TableMoney.string(stack)
        }

        XCTAssertEqual(seats.reduce(Decimal(0)) { $0 + $1.amountDecimal }, 60)
        XCTAssertEqual(seats.first { $0.playerKey == "cal" }?.amountDecimal, 21)

        let nextHand = try HandRound.start(
            seats: seats,
            dealerSeat: HandRound.nextDealerSeat(after: hand.dealerSeat, seats: seats),
            ante: 1,
            handNumber: hand.handNumber + 1
        )

        XCTAssertEqual(nextHand.handNumber, 2)
        XCTAssertEqual(nextHand.dealerSeat, 2)
        XCTAssertEqual(nextHand.actingSeat, 4)
        XCTAssertEqual(nextHand.pot, 0)
        XCTAssertEqual(nextHand.street, .preflop)
        XCTAssertTrue(nextHand.board.isEmpty)
        XCTAssertEqual(nextHand.seat(forPlayerKey: "cal")?.stackDecimal, 21)
    }

    func testTheButtonMovesOnForTheNextHand() {
        XCTAssertEqual(HandRound.nextDealerSeat(after: 1, seats: threeHandedTable()), 2)
        XCTAssertEqual(HandRound.nextDealerSeat(after: 4, seats: threeHandedTable()), 1)
    }

    func testSettlingTheSameHandTwicePaysItOnce() throws {
        var hand = try HandRound.start(seats: headsUpTable(), dealerSeat: nil, ante: 1)
        hand = try HandRound.apply(move: .fold, playerKey: "ben", to: hand)

        XCTAssertEqual(HandRound.stacksAfter(hand), HandRound.stacksAfter(hand))
        XCTAssertEqual(HandRound.stacksAfter(hand)["ana"], 20)
    }

    // MARK: - Amounts

    func testEveryMoveBumpsTheRevisionSoTheNewestOneWins() throws {
        let hand = try HandRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 1)
        let next = try HandRound.apply(move: .call, playerKey: "ben", to: hand)

        XCTAssertEqual(next.revision, hand.revision + 1)
        XCTAssertEqual(next.id, hand.id)
    }

    func testSuggestedBetDoublesWhatIsInFront() throws {
        var hand = try HandRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 2)
        XCTAssertEqual(HandRound.suggestedBet(in: hand, forPlayerKey: "ben"), 4)

        hand = try HandRound.apply(move: .bet, amount: 5, playerKey: "ben", to: hand)
        XCTAssertEqual(HandRound.suggestedBet(in: hand, forPlayerKey: "cal"), 10)
    }

    func testSuggestedBetOnACheckedFlopIsHalfThePot() throws {
        var hand = try HandRound.start(seats: threeHandedTable(), dealerSeat: nil, ante: 2)
        for key in ["ben", "cal", "ana"] {
            hand = try HandRound.apply(move: .call, playerKey: key, to: hand)
        }

        XCTAssertEqual(hand.street, .flop)
        XCTAssertEqual(hand.pot, 6)
        XCTAssertEqual(HandRound.suggestedBet(in: hand, forPlayerKey: "ben"), 3)
    }

    func testABetIsCappedAtTheStackAndCountsAsAllIn() throws {
        let seats = [
            seat(1, key: "ana", amount: "20", isHost: true),
            seat(2, key: "ben", amount: "3")
        ]
        var hand = try HandRound.start(seats: seats, dealerSeat: nil, ante: 1)
        hand = try HandRound.apply(move: .bet, amount: 50, playerKey: "ben", to: hand)

        let ben = try XCTUnwrap(hand.seat(forPlayerKey: "ben"))
        XCTAssertEqual(ben.committedDecimal, 3)
        XCTAssertTrue(ben.isAllIn)
        XCTAssertEqual(hand.actingSeat, 1, "The all-in still has to be called")
    }

    func testStayingInNeverPutsInMoreThanTheStack() throws {
        let seats = [
            seat(1, key: "ana", amount: "20", isHost: true),
            seat(2, key: "ben", amount: "2")
        ]
        var hand = try HandRound.start(seats: seats, dealerSeat: nil, ante: 1)
        hand = try HandRound.apply(move: .call, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .bet, amount: 9, playerKey: "ana", to: hand)
        hand = try HandRound.apply(move: .call, playerKey: "ben", to: hand)

        XCTAssertEqual(hand.seat(forPlayerKey: "ben")?.committedDecimal, 2)
        XCTAssertEqual(hand.street, .showdown, "Nobody is left to bet, so the board runs out")
        XCTAssertEqual(moneyOnTheTable(hand), 22)
    }

    func testDefaultAnteIsAHundredthOfTheBuyIn() {
        XCTAssertEqual(TableAnte.defaultAmount(forBuyIn: 100), 1)
        XCTAssertEqual(TableAnte.defaultAmount(forBuyIn: 50), dec("0.5"))
        XCTAssertEqual(TableAnte.defaultAmount(forBuyIn: dec("0.2")), dec("0.01"))
        XCTAssertEqual(TableAnte.defaultAmount(forBuyIn: 0), 0)
    }

    // MARK: - Nothing is ever created or lost

    func testAnyHandTheTableCanPlayEndsWithTheMoneyItStartedWith() throws {
        var generator = SystemRandomNumberGenerator()

        for round in 0..<200 {
            let seats = [
                seat(1, key: "ana", amount: "20", isHost: true),
                seat(2, key: "ben", amount: String(Int.random(in: 1...20, using: &generator))),
                seat(4, key: "cal", amount: String(Int.random(in: 1...20, using: &generator)))
            ]
            let start = seats.reduce(Decimal(0)) { $0 + $1.amountDecimal }
            var hand = try HandRound.start(seats: seats, dealerSeat: nil, ante: 1)

            var moves = 0
            while let actingSeat = hand.actingSeat, moves < 60 {
                moves += 1
                let playerKey = try XCTUnwrap(hand.seat(at: actingSeat)?.playerKey)
                hand = try HandRound.apply(
                    move: randomMove(in: hand, forPlayerKey: playerKey, using: &generator),
                    amount: HandRound.suggestedBet(in: hand, forPlayerKey: playerKey),
                    playerKey: playerKey,
                    to: hand
                )
            }

            XCTAssertNil(hand.actingSeat, "Hand \(round) never finished being bet")
            XCTAssertTrue(hand.isComplete, "Hand \(round) never paid out")
            XCTAssertFalse(hand.winnerSeats.isEmpty, "Hand \(round) has no winner")
            XCTAssertEqual(moneyOnTheTable(hand), start, "Hand \(round) invented or lost money")
        }
    }

    private func randomMove(
        in hand: SharedTableHand,
        forPlayerKey playerKey: String,
        using generator: inout SystemRandomNumberGenerator
    ) -> HandMove {
        let owed = hand.amountToCall(forPlayerKey: playerKey)
        let canBet = HandRound.suggestedBet(in: hand, forPlayerKey: playerKey) > hand.callTarget
        var moves: [HandMove] = owed > 0 ? [.call, .fold] : [.check]
        if canBet {
            moves.append(.bet)
        }
        return moves.randomElement(using: &generator) ?? .fold
    }
}

final class SharedTableHandDecodingTests: XCTestCase {
    /// The shape a build before cards were dealt wrote into the cloud row.
    private let handFromAnOlderBuild = """
    {
      "id": "6F9619FF-8B86-D011-B42D-00CF4FC964FF",
      "handNumber": 3,
      "revision": 7,
      "dealerSeat": 1,
      "ante": "1",
      "actingSeat": 2,
      "winnerSeat": 4,
      "seats": [
        {
          "id": "6F9619FF-8B86-D011-B42D-00CF4FC964F1",
          "seatNumber": 1,
          "playerKey": "ana",
          "playerName": "Ana",
          "stack": "20",
          "committed": "1",
          "hasActed": true,
          "isFolded": false
        },
        {
          "id": "6F9619FF-8B86-D011-B42D-00CF4FC964F2",
          "seatNumber": 4,
          "playerKey": "cal",
          "playerName": "Cal",
          "stack": "20",
          "committed": "1",
          "hasActed": true,
          "isFolded": false
        }
      ]
    }
    """

    func testAHandFromAnOlderBuildStillReadsAndIsDealtAgain() throws {
        let data = Data(handFromAnOlderBuild.utf8)
        let hand = try JSONDecoder().decode(SharedTableHand.self, from: data)

        XCTAssertEqual(hand.handNumber, 3)
        XCTAssertEqual(hand.street, .preflop)
        XCTAssertEqual(hand.winnerSeats, [4], "The one winner it knew about is kept")
        XCTAssertEqual(hand.seat(at: 1)?.streetCommittedDecimal, 1)
        XCTAssertTrue(hand.board.isEmpty)
        XCTAssertTrue(hand.needsRedeal, "It has no cards, so it cannot be played to a showdown")
    }

    func testAHandDealtByThisBuildTravelsThereAndBack() throws {
        let seats = [
            SharedTableSeat(
                id: UUID(),
                seatNumber: 1,
                playerName: "Ana",
                handle: nil,
                playerKey: "ana",
                amount: "20",
                isHost: true
            ),
            SharedTableSeat(
                id: UUID(),
                seatNumber: 2,
                playerName: "Ben",
                handle: nil,
                playerKey: "ben",
                amount: "20",
                isHost: false
            )
        ]
        var hand = try HandRound.start(seats: seats, dealerSeat: nil, ante: 1)
        hand = try HandRound.apply(move: .call, playerKey: "ben", to: hand)

        let data = try JSONEncoder().encode(hand)
        let decoded = try JSONDecoder().decode(SharedTableHand.self, from: data)

        XCTAssertEqual(decoded, hand)
        XCTAssertFalse(decoded.needsRedeal)
        XCTAssertEqual(decoded.version, SharedTableHand.currentVersion)
    }
}
