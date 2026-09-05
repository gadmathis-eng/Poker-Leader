import XCTest
@testable import PokerLeader

final class PlayingCardTests: XCTestCase {
    func testCardsReadAsTheirCode() {
        XCTAssertEqual(PlayingCard(rank: 14, suit: .spades).code, "As")
        XCTAssertEqual(PlayingCard(rank: 10, suit: .hearts).code, "Th")
        XCTAssertEqual(PlayingCard(rank: 2, suit: .clubs).code, "2c")
    }

    func testACodeReadsBackAsTheSameCard() {
        XCTAssertEqual(PlayingCard(code: "Kd"), PlayingCard(rank: 13, suit: .diamonds))
        XCTAssertEqual(PlayingCard(code: "7h"), PlayingCard(rank: 7, suit: .hearts))
        XCTAssertNil(PlayingCard(code: "1s"))
        XCTAssertNil(PlayingCard(code: "Ax"))
        XCTAssertNil(PlayingCard(code: "A"))
    }

    func testACardTravelsAsOneString() throws {
        let card = PlayingCard(rank: 12, suit: .hearts)
        let data = try JSONEncoder().encode([card])

        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"Qh\"]")
        XCTAssertEqual(try JSONDecoder().decode([PlayingCard].self, from: data), [card])
    }

    func testADeckHasEveryCardOnce() {
        let deck = CardDeck.shuffled()

        XCTAssertEqual(deck.count, CardDeck.cardCount)
        XCTAssertEqual(Set(deck).count, CardDeck.cardCount)
    }

    func testCardsAreNamedForReadingOutLoud() {
        XCTAssertEqual(PlayingCard(code: "As")?.accessibilityName, "ace of spades")
        XCTAssertEqual(PlayingCard(code: "6d")?.rankNamePlural, "sixes")
        XCTAssertEqual(PlayingCard(code: "Jc")?.rankNamePlural, "jacks")
    }
}

final class PokerHandEvaluatorTests: XCTestCase {
    private func rank(_ codes: [String]) -> PokerHandRank {
        guard let rank = PokerHandEvaluator.best(from: CardDeck.deck(codes)) else {
            XCTFail("\(codes) should make a hand")
            return PokerHandRank(category: .highCard, tiebreakers: [], cards: [])
        }
        return rank
    }

    // MARK: - Categories

    func testEveryHandIsNamedTheWayItIsCalledAtTheTable() {
        XCTAssertEqual(rank(["As", "Ks", "Qs", "Js", "Ts"]).summary, "Royal flush")
        XCTAssertEqual(rank(["9h", "8h", "7h", "6h", "5h"]).summary, "Straight flush, nine high")
        XCTAssertEqual(rank(["9h", "9d", "9c", "9s", "5h"]).summary, "Four of a kind, nines")
        XCTAssertEqual(rank(["Kh", "Kd", "Kc", "2s", "2h"]).summary, "Full house, kings full of twos")
        XCTAssertEqual(rank(["Ah", "Jh", "8h", "5h", "3h"]).summary, "Flush, ace high")
        XCTAssertEqual(rank(["Qs", "Jh", "Td", "9c", "8h"]).summary, "Straight, queen high")
        XCTAssertEqual(rank(["7s", "7h", "7d", "Kc", "4h"]).summary, "Three of a kind, sevens")
        XCTAssertEqual(rank(["As", "Ah", "8d", "8c", "3h"]).summary, "Two pair, aces and eights")
        XCTAssertEqual(rank(["Js", "Jh", "9d", "6c", "3h"]).summary, "Pair of jacks")
        XCTAssertEqual(rank(["As", "Jh", "9d", "6c", "3h"]).summary, "Ace high")
    }

    func testCategoriesBeatEachOtherInOrder() {
        XCTAssertTrue(rank(["9h", "8h", "7h", "6h", "5h"]) > rank(["9h", "9d", "9c", "9s", "5h"]))
        XCTAssertTrue(rank(["9h", "9d", "9c", "9s", "5h"]) > rank(["Kh", "Kd", "Kc", "2s", "2h"]))
        XCTAssertTrue(rank(["Kh", "Kd", "Kc", "2s", "2h"]) > rank(["Ah", "Jh", "8h", "5h", "3h"]))
        XCTAssertTrue(rank(["Ah", "Jh", "8h", "5h", "3h"]) > rank(["Qs", "Jh", "Td", "9c", "8h"]))
        XCTAssertTrue(rank(["Qs", "Jh", "Td", "9c", "8h"]) > rank(["7s", "7h", "7d", "Kc", "4h"]))
        XCTAssertTrue(rank(["7s", "7h", "7d", "Kc", "4h"]) > rank(["As", "Ah", "8d", "8c", "3h"]))
        XCTAssertTrue(rank(["As", "Ah", "8d", "8c", "3h"]) > rank(["Js", "Jh", "9d", "6c", "3h"]))
        XCTAssertTrue(rank(["Js", "Jh", "9d", "6c", "3h"]) > rank(["As", "Jh", "9d", "6c", "3h"]))
    }

    // MARK: - Straights

    func testTheWheelIsAFiveHighStraight() {
        let wheel = rank(["As", "2h", "3d", "4c", "5s"])

        XCTAssertEqual(wheel.category, .straight)
        XCTAssertEqual(wheel.summary, "Straight, five high")
        XCTAssertTrue(rank(["6s", "2h", "3d", "4c", "5s"]) > wheel)
    }

    func testAceHighAndAceLowAreNotTheSameStraight() {
        XCTAssertTrue(rank(["As", "Kh", "Qd", "Jc", "Ts"]) > rank(["As", "2h", "3d", "4c", "5s"]))
    }

    func testFiveCardsWithAGapAreNotAStraight() {
        XCTAssertEqual(rank(["9s", "8h", "7d", "6c", "4s"]).category, .highCard)
    }

    // MARK: - Kickers

    func testTheKickerSplitsTwoOfTheSameHand() {
        XCTAssertTrue(rank(["Ks", "Kh", "Ad", "7c", "3s"]) > rank(["Ks", "Kh", "Qd", "7c", "3s"]))
        XCTAssertTrue(rank(["As", "Ah", "9d", "9c", "Ks"]) > rank(["As", "Ah", "9d", "9c", "Qs"]))
    }

    func testTheSameHandTwiceIsATie() {
        let left = rank(["As", "Ah", "9d", "9c", "Ks"])
        let right = rank(["Ad", "Ac", "9h", "9s", "Kh"])

        XCTAssertFalse(left > right)
        XCTAssertFalse(right > left)
    }

    // MARK: - Seven cards

    func testTheBestFiveOutOfSevenAreKept() {
        let flush = rank(["Ah", "Kh", "2h", "7h", "9h", "As", "Ad"])

        XCTAssertEqual(flush.category, .flush)
        XCTAssertEqual(flush.cards.count, 5)
        XCTAssertTrue(flush.cards.allSatisfy { $0.suit == .hearts })
    }

    func testTwoCardsPlusTheBoardMakeAHand() {
        let hole = CardDeck.deck(["Ah", "Kh"])
        let board = CardDeck.deck(["Qh", "Jh", "Th", "2c", "3d"])

        XCTAssertEqual(PokerHandEvaluator.best(from: hole + board)?.summary, "Royal flush")
    }

    func testFewerThanFiveCardsMakeNoHand() {
        XCTAssertNil(PokerHandEvaluator.best(from: CardDeck.deck(["Ah", "Kh", "Qh", "Jh"])))
    }
}
