import XCTest
@testable import PokerLeader

final class HandNarrationTests: XCTestCase {
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

    /// A deck whose first cards are dealt in a known order, then whatever is left.
    private func stacked(_ codes: [String]) -> [PlayingCard] {
        let known = CardDeck.deck(codes)
        XCTAssertEqual(known.count, codes.count, "\(codes) has a card code in it that is not a card")
        return known + CardDeck.ordered.filter { !known.contains($0) }
    }

    private func narration(_ hand: SharedTableHand?, for playerKey: String) -> HandNarration {
        HandNarration(hand: hand, localPlayerKey: playerKey, currencyCode: "GBP")
    }

    // MARK: - Before there is a hand

    func testAnEmptyTableAsksYouToShareIt() {
        let told = narration(nil, for: "ana")

        XCTAssertEqual(told.turn, .waitingForPlayers)
        XCTAssertEqual(told.boardTitle, "Waiting for players")
        XCTAssertEqual(told.title, "Waiting for players")
        XCTAssertTrue(told.detail.contains("Share the table"))
        XCTAssertNil(told.stackLine)
        XCTAssertNil(told.yourHand)
    }

    // MARK: - Your turn

    func testTheAnteIsWhatYouAreAskedForBeforeTheFlop() throws {
        let hand = try HandRound.start(
            seats: headsUpTable(),
            dealerSeat: nil,
            ante: 1,
            deck: stacked(["as", "2c", "kd", "3c"])
        )
        let told = narration(hand, for: "ben")

        XCTAssertEqual(told.turn, .toAct(toCall: 1))
        XCTAssertEqual(told.title, "Are you in?")
        XCTAssertEqual(told.detail, "Ace king offsuit · Ante £1 to stay in")
        XCTAssertEqual(told.stackLine, "Ante £1 · £20 behind")
        XCTAssertEqual(told.boardStatus, "Your turn")
        XCTAssertEqual(told.boardTitle, "Hand 1 · Pre-flop")
    }

    func testTheStreetIsNamedOnceThereAreCardsOnTheTable() throws {
        var hand = try HandRound.start(
            seats: headsUpTable(),
            dealerSeat: nil,
            ante: 1,
            deck: stacked(["as", "kd", "2c", "3c", "ah", "7d", "9s"])
        )
        hand = try HandRound.apply(move: .call, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .call, playerKey: "ana", to: hand)

        let told = narration(hand, for: hand.seat(at: hand.actingSeat ?? 0)?.playerKey ?? "")

        XCTAssertEqual(hand.street, .flop)
        XCTAssertEqual(told.boardTitle, "Hand 1 · Flop")
        XCTAssertEqual(told.title, "Your turn on the flop")
        XCTAssertTrue(told.detail.hasSuffix("Nothing to put in yet"))
    }

    func testMoneyAddedMidHandIsSaidToBeWaiting() throws {
        var hand = try HandRound.start(seats: headsUpTable(), dealerSeat: nil, ante: 1)
        hand = try XCTUnwrap(HandRound.addingMoney(10, playerKey: "ben", to: hand))

        let told = narration(hand, for: "ben")

        XCTAssertEqual(told.stackLine, "Ante £1 · £20 behind · £10 joins next hand")
    }

    // MARK: - Waiting on somebody else

    func testWaitingNamesWhoeverTheTableIsWaitingFor() throws {
        let hand = try HandRound.start(seats: headsUpTable(), dealerSeat: nil, ante: 1)
        let told = narration(hand, for: "ana")

        XCTAssertEqual(told.turn, .waitingForOthers)
        XCTAssertEqual(told.title, "Waiting for Ben")
        XCTAssertEqual(told.boardStatus, "Waiting for Ben")
        XCTAssertEqual(told.detail, "You are in for £0.")
    }

    func testFoldingLeavesYouWatching() throws {
        var hand = try HandRound.start(
            seats: [
                seat(1, key: "ana", amount: "20", isHost: true),
                seat(2, key: "ben", amount: "20"),
                seat(3, key: "cal", amount: "20")
            ],
            dealerSeat: nil,
            ante: 1
        )
        hand = try HandRound.apply(move: .fold, playerKey: "ben", to: hand)

        let told = narration(hand, for: "ben")

        XCTAssertEqual(told.turn, .folded)
        XCTAssertEqual(told.title, "You folded")
        XCTAssertEqual(told.detail, "Waiting for Cal")
        XCTAssertNil(told.yourHand)
    }

    func testSittingDownMidHandWaitsForTheNextOne() throws {
        let hand = try HandRound.start(seats: headsUpTable(), dealerSeat: nil, ante: 1)
        let told = narration(hand, for: "late-arrival")

        XCTAssertEqual(told.turn, .notDealtIn)
        XCTAssertEqual(told.title, "You are in from the next hand")
        XCTAssertEqual(told.detail, "This hand started before you sat down.")
        XCTAssertNil(told.stackLine)
    }

    // MARK: - The end of a hand

    func testTakingThePotIsSaidInTheFirstPerson() throws {
        var hand = try HandRound.start(seats: headsUpTable(), dealerSeat: nil, ante: 1)
        hand = try HandRound.apply(move: .call, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .fold, playerKey: "ana", to: hand)

        let benWasTold = narration(hand, for: "ben")
        let anaWasTold = narration(hand, for: "ana")

        XCTAssertTrue(hand.isComplete)
        XCTAssertEqual(benWasTold.turn, .handOver)
        XCTAssertEqual(benWasTold.title, "You take £1")
        XCTAssertEqual(anaWasTold.title, "Ben takes £1")
        XCTAssertEqual(benWasTold.boardTitle, "Hand 1")
        XCTAssertEqual(benWasTold.boardStatus, "Ben wins")
        XCTAssertNil(benWasTold.stackLine, "a finished hand has paid out, so what is behind you is the seat's job")
    }

    func testASplitPotNamesEverybodyInIt() throws {
        var hand = try HandRound.start(
            seats: headsUpTable(),
            dealerSeat: nil,
            ante: 1,
            deck: stacked(["ah", "ad", "kh", "kd", "2c", "7d", "9s", "js", "qc"])
        )
        hand = try HandRound.apply(move: .call, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .call, playerKey: "ana", to: hand)
        while !hand.isComplete, let acting = hand.actingSeat, let key = hand.seat(at: acting)?.playerKey {
            hand = try HandRound.apply(move: .check, playerKey: key, to: hand)
        }

        let told = narration(hand, for: "ana")

        XCTAssertEqual(hand.winnerSeats.count, 2)
        XCTAssertEqual(told.boardStatus, "Split pot")
        XCTAssertTrue(told.title.hasPrefix("You and Ben split "), told.title)
        XCTAssertEqual(told.detail, hand.resultSummary)
    }
}
