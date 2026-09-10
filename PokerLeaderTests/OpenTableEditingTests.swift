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

    func testEachPlayerKeepsTheirOwnBuyIn() throws {
        var seats = try SharedTableSeating.occupy(
            seats: [],
            seatNumber: 1,
            playerKey: "host",
            playerName: "Alex",
            handle: nil,
            amount: 50,
            isHost: true
        )
        seats = try SharedTableSeating.occupy(
            seats: seats,
            seatNumber: 3,
            playerKey: "guest",
            playerName: "Ben",
            handle: nil,
            amount: 15,
            isHost: false
        )

        XCTAssertEqual(seats.map(\.amountDecimal), [50, 15])
        XCTAssertEqual(seats.map(\.boughtInDecimal), [50, 15])
        XCTAssertEqual(seats.map(\.playerKey), ["host", "guest"])
    }

    func testSittingAgainKeepsWhatTheyPutInWhenTheStackMoves() throws {
        var seats = try SharedTableSeating.occupy(
            seats: [],
            seatNumber: 1,
            playerKey: "host",
            playerName: "Alex",
            handle: nil,
            amount: 20,
            isHost: true
        )
        seats[0].amount = "35"
        seats = try SharedTableSeating.occupy(
            seats: seats,
            seatNumber: 3,
            playerKey: "host",
            playerName: "Alex",
            handle: nil,
            amount: 35,
            isHost: true
        )

        XCTAssertEqual(seats.count, 1)
        XCTAssertEqual(seats[0].seatNumber, 3)
        XCTAssertEqual(seats[0].amountDecimal, 35)
        XCTAssertEqual(seats[0].boughtInDecimal, 20)
    }

    func testASeatFromAnOlderBuildTreatsTheStackAsWhatTheyPutIn() throws {
        let json = """
        {
          "id": "6F9619FF-8B86-D011-B42D-00CF4FC964F0",
          "seatNumber": 1,
          "playerName": "Ana",
          "playerKey": "ana",
          "amount": "20",
          "isHost": true
        }
        """
        let seat = try JSONDecoder().decode(SharedTableSeat.self, from: Data(json.utf8))

        XCTAssertEqual(seat.amountDecimal, 20)
        XCTAssertEqual(seat.boughtInDecimal, 20)
        XCTAssertEqual(seat.boughtIn, "20")
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
