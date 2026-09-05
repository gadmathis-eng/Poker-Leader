import XCTest
@testable import PokerLeader

final class TableNamingTests: XCTestCase {
    func testKeepsATrimmedName() {
        XCTAssertEqual(TableNaming.normalized("  Friday game  "), "Friday game")
    }

    func testDropsBlankNames() {
        XCTAssertNil(TableNaming.normalized("   "))
        XCTAssertNil(TableNaming.normalized(nil))
    }

    func testTitleFallsBackToTheInviteCode() {
        XCTAssertEqual(TableNaming.title(name: nil, inviteCode: "ab12cd"), "Table AB12CD")
        XCTAssertEqual(TableNaming.title(name: " ", inviteCode: "ab12cd"), "Table AB12CD")
    }

    func testTitleUsesTheName() {
        XCTAssertEqual(TableNaming.title(name: " Friday game ", inviteCode: "AB12CD"), "Friday game")
    }
}

final class SharedTableSeatingRemovalTests: XCTestCase {
    func testRemovingASeatKeepsTheOtherPlayers() throws {
        var seats = try SharedTableSeating.occupy(
            seats: [],
            seatNumber: 1,
            playerKey: "host",
            playerName: "Alex",
            handle: nil,
            amount: 20,
            isHost: true
        )
        seats = try SharedTableSeating.occupy(
            seats: seats,
            seatNumber: 4,
            playerKey: "guest",
            playerName: "Ben",
            handle: nil,
            amount: 10,
            isHost: false
        )

        let remaining = SharedTableSeating.removing(playerKey: "guest", from: seats)

        XCTAssertEqual(remaining.map(\.playerKey), ["host"])
    }

    func testRemovingAPlayerWithoutASeatChangesNothing() throws {
        let seats = try SharedTableSeating.occupy(
            seats: [],
            seatNumber: 2,
            playerKey: "host",
            playerName: "Alex",
            handle: nil,
            amount: 20,
            isHost: true
        )

        XCTAssertEqual(SharedTableSeating.removing(playerKey: "nobody", from: seats), seats)
    }
}
