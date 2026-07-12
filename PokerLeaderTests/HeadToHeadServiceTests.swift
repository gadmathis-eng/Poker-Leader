import XCTest
@testable import PokerLeader

final class HeadToHeadServiceTests: XCTestCase {
    func testStatsFromSharedSessions() {
        let circle = CircleModel(name: "Test", shortCode: "TS", currencyCode: "GBP")
        let alex = MemberModel(displayName: "Alex", initial: "A")
        let ben = MemberModel(displayName: "Ben", initial: "B")
        alex.circle = circle
        ben.circle = circle
        circle.members = [alex, ben]

        let sessionOne = SessionModel(
            title: "Night 1",
            status: .settled,
            buyInAmount: 20,
            currencyCode: "GBP",
            players: [
                SessionPlayerModel(displayName: "Alex", initial: "A", net: 50, memberId: alex.id),
                SessionPlayerModel(displayName: "Ben", initial: "B", net: -50, memberId: ben.id)
            ]
        )
        let sessionTwo = SessionModel(
            title: "Night 2",
            status: .settled,
            buyInAmount: 20,
            currencyCode: "GBP",
            players: [
                SessionPlayerModel(displayName: "Alex", initial: "A", net: -10, memberId: alex.id),
                SessionPlayerModel(displayName: "Ben", initial: "B", net: 10, memberId: ben.id)
            ]
        )
        sessionOne.circle = circle
        sessionTwo.circle = circle
        circle.sessions = [sessionOne, sessionTwo]

        let stats = HeadToHeadService.stats(
            circle: circle,
            memberAId: alex.id,
            memberAName: alex.displayName,
            memberBId: ben.id,
            memberBName: ben.displayName
        )

        XCTAssertEqual(stats?.sharedGames, 2)
        XCTAssertEqual(stats?.leaderName, "Alex")
        XCTAssertEqual(stats?.leaderSessionWins, 1)
        XCTAssertEqual(stats?.trailingSessionWins, 1)
        XCTAssertEqual(stats?.leaderNet, 80)
        XCTAssertEqual(stats?.biggestLeaderWin, 100)
    }
}
