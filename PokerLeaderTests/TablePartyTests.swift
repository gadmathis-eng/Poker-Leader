import XCTest
@testable import PokerLeader

final class TablePartyTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TablePartyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeParty() -> TableParty {
        TableParty(defaults: defaults)
    }

    func testCreatorBecomesLeader() {
        let party = makeParty()
        let creator = party.join(name: "Alex", seat: 1, stack: 100, isYou: true)

        XCTAssertNotNil(creator)
        XCTAssertEqual(party.leaderId, creator?.id)
        XCTAssertTrue(party.youAreLeader)
    }

    func testLaterJoinersDoNotTakeLeadership() {
        let party = makeParty()
        let creator = party.join(name: "Alex", seat: 1, stack: 100)
        party.join(name: "Ben", seat: 2, stack: 100)
        party.join(name: "Cara", seat: 3, stack: 100)

        XCTAssertEqual(party.leaderId, creator?.id)
        XCTAssertEqual(party.players.count, 3)
    }

    func testLeadershipPassesToSecondPlayerWhenLeaderLeaves() {
        let party = makeParty()
        let creator = party.join(name: "Alex", seat: 1, stack: 100)
        let second = party.join(name: "Ben", seat: 2, stack: 100)
        party.join(name: "Cara", seat: 3, stack: 100)

        party.leave(creator!.id)

        XCTAssertEqual(party.leaderId, second?.id)
    }

    func testLeadershipFollowsJoinOrderNotSeatOrder() {
        let party = makeParty()
        let creator = party.join(name: "Alex", seat: 8, stack: 100)
        let second = party.join(name: "Ben", seat: 5, stack: 100)
        party.join(name: "Cara", seat: 1, stack: 100)

        party.leave(creator!.id)

        XCTAssertEqual(party.leaderId, second?.id, "Seat 1 should not inherit leadership over the earlier joiner")
    }

    func testNonLeaderLeavingKeepsLeader() {
        let party = makeParty()
        let creator = party.join(name: "Alex", seat: 1, stack: 100)
        let second = party.join(name: "Ben", seat: 2, stack: 100)

        party.leave(second!.id)

        XCTAssertEqual(party.leaderId, creator?.id)
    }

    func testLeaderIsClearedWhenEveryoneLeaves() {
        let party = makeParty()
        let creator = party.join(name: "Alex", seat: 1, stack: 100)

        party.leave(creator!.id)

        XCTAssertNil(party.leaderId)
        XCTAssertTrue(party.players.isEmpty)
    }

    func testCannotStartBelowMinimumPlayers() {
        let party = makeParty()
        party.join(name: "Alex", seat: 1, stack: 100)

        XCTAssertFalse(party.canStart)
        party.startGame()
        XCTAssertFalse(party.isStarted)
    }

    func testLeaderCanStartWithEnoughPlayers() {
        let party = makeParty()
        party.join(name: "Alex", seat: 1, stack: 100)
        party.join(name: "Ben", seat: 2, stack: 100)

        XCTAssertTrue(party.canStart)
        party.startGame()
        XCTAssertTrue(party.isStarted)
    }

    func testSeatCannotBeTakenTwice() {
        let party = makeParty()
        party.join(name: "Alex", seat: 1, stack: 100)
        let duplicate = party.join(name: "Ben", seat: 1, stack: 100)

        XCTAssertNil(duplicate)
        XCTAssertEqual(party.players.count, 1)
    }

    func testYouCanOnlyJoinOnce() {
        let party = makeParty()
        party.join(name: "Alex", seat: 1, stack: 100, isYou: true)
        let second = party.join(name: "Alex", seat: 2, stack: 100, isYou: true)

        XCTAssertNil(second)
        XCTAssertEqual(party.players.count, 1)
    }

    func testAddToStackIncreasesPlayerStack() {
        let party = makeParty()
        let player = party.join(name: "Alex", seat: 1, stack: 20)

        party.addToStack(35, for: player!.id)

        XCTAssertEqual(party.players.first?.stack, 55)
    }

    func testAddToStackIgnoresNonPositiveAmounts() {
        let party = makeParty()
        let player = party.join(name: "Alex", seat: 1, stack: 20)

        party.addToStack(0, for: player!.id)
        party.addToStack(-10, for: player!.id)

        XCTAssertEqual(party.players.first?.stack, 20)
    }

    func testAddToStackOnlyAffectsTargetPlayer() {
        let party = makeParty()
        let alex = party.join(name: "Alex", seat: 1, stack: 20)
        party.join(name: "Ben", seat: 2, stack: 20)

        party.addToStack(50, for: alex!.id)

        XCTAssertEqual(party.players[0].stack, 70)
        XCTAssertEqual(party.players[1].stack, 20)
    }

    func testAddedStackPersists() {
        let party = makeParty()
        let player = party.join(name: "Alex", seat: 1, stack: 20)
        party.addToStack(40, for: player!.id)

        let restored = makeParty()

        XCTAssertEqual(restored.players.first?.stack, 60)
    }

    func testStatePersistsAcrossInstances() {
        let party = makeParty()
        let creator = party.join(name: "Alex", seat: 1, stack: 100, isYou: true)
        party.join(name: "Ben", seat: 2, stack: 100)
        party.startGame()

        let restored = makeParty()

        XCTAssertEqual(restored.players.count, 2)
        XCTAssertEqual(restored.leaderId, creator?.id)
        XCTAssertTrue(restored.isStarted)
    }

    func testStartingIsResetWhenTableEmpties() {
        let party = makeParty()
        let creator = party.join(name: "Alex", seat: 1, stack: 100)
        let second = party.join(name: "Ben", seat: 2, stack: 100)
        party.startGame()

        party.leave(creator!.id)
        party.leave(second!.id)

        XCTAssertFalse(party.isStarted)
        XCTAssertNil(party.leaderId)
    }
}
