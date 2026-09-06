import XCTest
import SwiftData
@testable import PokerLeader

@MainActor
final class TableRepositoryStartTests: XCTestCase {
    private let activeInviteCodeKey = "activeTableInviteCode"
    private let playerKeyKey = "tablePlayerKey"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: activeInviteCodeKey)
        UserDefaults.standard.set("host-key", forKey: playerKeyKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: activeInviteCodeKey)
        UserDefaults.standard.removeObject(forKey: playerKeyKey)
        super.tearDown()
    }

    func testStartHostedTableCreatesANamedTable() throws {
        let repo = TableRepository(context: try makeContext())

        let table = try repo.startHostedTable(
            name: "Uni Boys",
            sessionCurrencyCode: "GBP",
            hostDisplayName: "Alex"
        )

        XCTAssertEqual(table.name, "Uni Boys")
        XCTAssertEqual(table.sessionCurrencyCode, "GBP")
        XCTAssertEqual(table.hostDisplayName, "Alex")
        XCTAssertTrue(table.isHostLocally)
        XCTAssertEqual(table.inviteCode, repo.activeInviteCode)
    }

    func testStartHostedTableReusesTheActiveHostedTable() throws {
        let repo = TableRepository(context: try makeContext())
        let first = try repo.startHostedTable(
            name: "Friday",
            sessionCurrencyCode: "USD",
            hostDisplayName: "Alex"
        )

        let second = try repo.startHostedTable(
            name: "Uni Boys",
            sessionCurrencyCode: "GBP",
            hostDisplayName: "Alex"
        )

        XCTAssertEqual(first.inviteCode, second.inviteCode)
        XCTAssertEqual(second.name, "Uni Boys")
        XCTAssertEqual(second.sessionCurrencyCode, "GBP")
    }

    func testStartHostedTableDoesNotReuseAJoinedTable() throws {
        let context = try makeContext()
        let joined = OpenTableModel(
            inviteCode: "JOIN01",
            name: "Friend's table",
            hostDisplayName: "Ben",
            hostPlayerKey: "guest-key",
            sessionCurrencyCode: "EUR",
            isHostLocally: false
        )
        context.insert(joined)
        try context.save()

        let repo = TableRepository(context: context)
        repo.makeActive(joined)

        let hosted = try repo.startHostedTable(
            name: "Uni Boys",
            sessionCurrencyCode: "GBP",
            hostDisplayName: "Alex"
        )

        XCTAssertNotEqual(hosted.inviteCode, joined.inviteCode)
        XCTAssertTrue(hosted.isHostLocally)
        XCTAssertEqual(hosted.name, "Uni Boys")
        XCTAssertEqual(hosted.inviteCode, repo.activeInviteCode)
        XCTAssertFalse(joined.isHostLocally)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([OpenTableModel.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
