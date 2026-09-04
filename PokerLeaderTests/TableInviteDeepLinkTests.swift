import XCTest
@testable import PokerLeader

final class TableInviteDeepLinkTests: XCTestCase {
    func testBuildsHttpsShareURL() {
        XCTAssertEqual(
            TableInviteDeepLink.webURL(forInviteCode: "ab12cd").absoluteString,
            "https://potmaster.app/?table=AB12CD"
        )
    }

    func testParsesCustomSchemeTableLink() {
        let url = URL(string: "com.mathisgad.pokerleader://table/ab12cd")!
        XCTAssertEqual(TableInviteDeepLink.inviteCode(from: url), "AB12CD")
    }

    func testParsesHttpsTablePath() {
        let url = URL(string: "https://potmaster.app/table/xy34zt")!
        XCTAssertEqual(TableInviteDeepLink.inviteCode(from: url), "XY34ZT")
    }

    func testParsesWwwHttpsTablePathWithTrailingSlash() {
        let url = URL(string: "https://www.potmaster.app/table/seat01/")!
        XCTAssertEqual(TableInviteDeepLink.inviteCode(from: url), "SEAT01")
    }

    func testParsesHomepageTableQuery() {
        let url = URL(string: "https://potmaster.app/?table=joinme")!
        XCTAssertEqual(TableInviteDeepLink.inviteCode(from: url), "JOINME")
    }

    func testParsesHttpsTableQueryCode() {
        let url = URL(string: "https://potmaster.app/table/?code=joinme")!
        XCTAssertEqual(TableInviteDeepLink.inviteCode(from: url), "JOINME")
    }

    func testIgnoresUnrelatedHttpsPaths() {
        let url = URL(string: "https://potmaster.app/privacy/")!
        XCTAssertNil(TableInviteDeepLink.inviteCode(from: url))
    }

    func testIgnoresCircleInviteLinks() {
        let url = URL(string: "com.mathisgad.pokerleader://join/ABC123")!
        XCTAssertNil(TableInviteDeepLink.inviteCode(from: url))
    }

    func testShareMessageIncludesTapableLink() {
        let message = TableInviteSharing.message(forInviteCode: "abc123", hostName: "Alex")
        XCTAssertTrue(message.contains("https://potmaster.app/?table=ABC123"))
        XCTAssertTrue(message.contains("Table code: ABC123"))
        XCTAssertTrue(message.contains("Alex's"))
    }
}

private struct DummyLocalizedError: LocalizedError {
    let errorDescription: String?
}

final class TableRepositoryErrorTests: XCTestCase {
    func testDetectsMissingOpenTablesSchemaCacheError() {
        let error = DummyLocalizedError(
            errorDescription: "Could not find the table 'public.open_tables' in the schema cache"
        )

        XCTAssertTrue(TableRepositoryError.isMissingOpenTablesSchema(error))
        XCTAssertEqual(TableRepositoryError.wrapping(error) as? TableRepositoryError, .schemaMissing)
    }

    func testDetectsPostgRESTMissingTableCode() {
        let error = DummyLocalizedError(
            errorDescription: "PGRST205: Could not find the table 'public.open_tables'"
        )

        XCTAssertTrue(TableRepositoryError.isMissingOpenTablesSchema(error))
    }

    func testDetectsMissingSeatMergeFunction() {
        let error = DummyLocalizedError(
            errorDescription: "PGRST202: Could not find the function public.merge_open_table_seat"
        )

        XCTAssertTrue(TableRepositoryError.isMissingOpenTablesSchema(error))
        XCTAssertEqual(TableRepositoryError.wrapping(error) as? TableRepositoryError, .schemaMissing)
    }

    func testIgnoresUnrelatedCloudErrors() {
        let error = DummyLocalizedError(errorDescription: "No table found for that code.")

        XCTAssertFalse(TableRepositoryError.isMissingOpenTablesSchema(error))
        XCTAssertFalse(TableRepositoryError.wrapping(error) is TableRepositoryError)
    }

    func testSchemaMissingMessageTellsHostToRunMigration() {
        XCTAssertTrue(
            TableRepositoryError.schemaMissing.localizedDescription.contains("open_tables.sql")
        )
    }

    func testMapsRemoteSeatTakenError() {
        let error = DummyLocalizedError(errorDescription: "seat taken")
        XCTAssertEqual(SharedTableSeatingError.matching(error), .seatTaken)
    }
}

final class SharedTableSeatingTests: XCTestCase {
    func testOccupiesAnOpenSeat() throws {
        let seats = try SharedTableSeating.occupy(
            seats: [],
            seatNumber: 3,
            playerKey: "p1",
            playerName: "Alex",
            handle: "@alex",
            amount: 20,
            isHost: true
        )

        XCTAssertEqual(seats.count, 1)
        XCTAssertEqual(seats[0].seatNumber, 3)
        XCTAssertEqual(seats[0].playerName, "Alex")
        XCTAssertTrue(seats[0].isHost)
    }

    func testMovesAPlayerToANewSeat() throws {
        let seated = try SharedTableSeating.occupy(
            seats: [],
            seatNumber: 1,
            playerKey: "p1",
            playerName: "Alex",
            handle: nil,
            amount: 20,
            isHost: true
        )
        let moved = try SharedTableSeating.occupy(
            seats: seated,
            seatNumber: 5,
            playerKey: "p1",
            playerName: "Alex",
            handle: nil,
            amount: 15,
            isHost: true
        )

        XCTAssertEqual(moved.count, 1)
        XCTAssertEqual(moved[0].seatNumber, 5)
        XCTAssertEqual(moved[0].amountDecimal, 15)
    }

    func testRejectsATakenSeat() throws {
        let seated = try SharedTableSeating.occupy(
            seats: [],
            seatNumber: 2,
            playerKey: "host",
            playerName: "Alex",
            handle: nil,
            amount: 20,
            isHost: true
        )

        XCTAssertThrowsError(
            try SharedTableSeating.occupy(
                seats: seated,
                seatNumber: 2,
                playerKey: "guest",
                playerName: "Ben",
                handle: nil,
                amount: 20,
                isHost: false
            )
        ) { error in
            XCTAssertEqual(error as? SharedTableSeatingError, .seatTaken)
        }
    }

    func testRejectsSeatsOutsideTheTable() {
        XCTAssertThrowsError(
            try SharedTableSeating.occupy(
                seats: [],
                seatNumber: 9,
                playerKey: "p1",
                playerName: "Alex",
                handle: nil,
                amount: 20,
                isHost: true
            )
        ) { error in
            XCTAssertEqual(error as? SharedTableSeatingError, .invalidSeat)
        }
    }
}
