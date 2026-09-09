import XCTest
import SwiftData
@testable import PokerLeader

final class SessionTableSeatingTests: XCTestCase {
    func testSeatsOnlyTheSessionMembers() {
        let host = MemberModel(displayName: "Alex", initial: "A", handle: "@alex", isCurrentUser: true)
        let guest = MemberModel(displayName: "Ben", initial: "B", handle: "@ben")
        let sittingOut = MemberModel(displayName: "Cal", initial: "C")

        let seats = SessionTableSeating.seats(
            from: [host, guest],
            moneyIn: [host.id: 40, guest.id: 20],
            standardBuyIn: 20,
            hostMemberId: host.id,
            hostPlayerKey: "host-key",
            preferredHandle: "@alex"
        )

        XCTAssertEqual(seats.map(\.playerName), ["Alex", "Ben"])
        XCTAssertFalse(seats.contains(where: { $0.playerName == sittingOut.displayName }))
        XCTAssertEqual(seats.map(\.amount), [40, 20])
        XCTAssertEqual(seats.first?.playerKey, "host-key")
        XCTAssertEqual(seats.last?.playerKey, guest.id.uuidString)
        XCTAssertEqual(seats.map(\.isHost), [true, false])
    }

    func testZeroMoneyInUsesTheStandardBuyIn() {
        let host = MemberModel(displayName: "Alex", initial: "A", isCurrentUser: true)
        let guest = MemberModel(displayName: "Ben", initial: "B")

        let seats = SessionTableSeating.seats(
            from: [host, guest],
            moneyIn: [host.id: 0, guest.id: 0],
            standardBuyIn: 20,
            hostMemberId: host.id,
            hostPlayerKey: "host-key",
            preferredHandle: "@alex"
        )

        XCTAssertEqual(seats.map(\.amount), [20, 20])
    }

    func testCapsTheTableAtEightSeats() {
        let members = (1...9).map { index in
            MemberModel(displayName: "P\(index)", initial: "P", isCurrentUser: index == 1)
        }

        let seats = SessionTableSeating.seats(
            from: members,
            moneyIn: [:],
            standardBuyIn: 10,
            hostMemberId: members[0].id,
            hostPlayerKey: "host-key",
            preferredHandle: "@you"
        )

        XCTAssertEqual(seats.count, 8)
        XCTAssertEqual(seats.map(\.playerName), (1...8).map { "P\($0)" })
    }
}

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
        XCTAssertTrue(table.seats.isEmpty)
    }

    func testCreateNewTableStartsAnUntitledHostedTable() throws {
        let repo = TableRepository(context: try makeContext())

        let table = try repo.startHostedTable(
            name: nil,
            sessionCurrencyCode: "USD",
            hostDisplayName: "Alex"
        )

        XCTAssertNil(table.name)
        XCTAssertEqual(table.displayTitle, "Table \(table.inviteCode)")
        XCTAssertEqual(table.sessionCurrencyCode, "USD")
        XCTAssertTrue(table.isHostLocally)
        XCTAssertTrue(table.seats.isEmpty)
        XCTAssertEqual(table.inviteCode, repo.activeInviteCode)
    }

    func testStartHostedTableStoresTheChosenAnte() throws {
        let repo = TableRepository(context: try makeContext())

        let ante = Decimal(string: "0.20") ?? 0
        let table = try repo.startHostedTable(
            name: nil,
            sessionCurrencyCode: "GBP",
            hostDisplayName: "Alex",
            anteAmount: ante
        )

        XCTAssertEqual(table.anteAmount, TableMoney.string(ante))
        XCTAssertEqual(table.anteDecimal, TableMoney.decimal(TableMoney.string(ante)))
        XCTAssertEqual(table.sessionCurrencyCode, "GBP")
        XCTAssertTrue(table.seats.isEmpty)
    }

    func testStartHostedTableAlwaysCreatesANewTable() throws {
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

        XCTAssertNotEqual(first.inviteCode, second.inviteCode)
        XCTAssertEqual(second.name, "Uni Boys")
        XCTAssertEqual(second.sessionCurrencyCode, "GBP")
        XCTAssertEqual(second.inviteCode, repo.activeInviteCode)
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

    func testStartHostedTableSeatsOnlyTheSessionPlayers() throws {
        let repo = TableRepository(context: try makeContext())
        let guestId = UUID()

        let table = try repo.startHostedTable(
            name: "Test 2",
            sessionCurrencyCode: "GBP",
            hostDisplayName: "Alex",
            sessionSeats: [
                SessionTableSeat(
                    playerKey: "host-key",
                    playerName: "nnnnnnnn",
                    handle: "@nnnnnnnn",
                    amount: 20,
                    isHost: true
                ),
                SessionTableSeat(
                    playerKey: guestId.uuidString,
                    playerName: "Mathis Test 1",
                    handle: nil,
                    amount: 20,
                    isHost: false
                )
            ]
        )

        XCTAssertEqual(table.seats.map(\.playerName), ["nnnnnnnn", "Mathis Test 1"])
        XCTAssertEqual(table.seats.map(\.seatNumber), [1, 2])
        XCTAssertEqual(table.seats.map(\.playerKey), ["host-key", guestId.uuidString])
        XCTAssertEqual(table.seats.map(\.isHost), [true, false])
        XCTAssertEqual(table.seats.map(\.amountDecimal), [20, 20])
    }

    func testDealNextHandStartsTheFollowingHandWithoutBeingAsked() throws {
        let repo = TableRepository(context: try makeContext())
        let table = try repo.startHostedTable(
            name: "Friday",
            sessionCurrencyCode: "GBP",
            hostDisplayName: "Ana",
            sessionSeats: [
                SessionTableSeat(
                    playerKey: "host-key",
                    playerName: "Ana",
                    handle: nil,
                    amount: 20,
                    isHost: true
                ),
                SessionTableSeat(
                    playerKey: "ben",
                    playerName: "Ben",
                    handle: nil,
                    amount: 20,
                    isHost: false
                )
            ]
        )
        repo.updateAnte(1, on: table)

        let first = try repo.dealHand(on: table)
        var finished = try HandRound.apply(move: .call, playerKey: "ben", to: first)
        finished = try HandRound.apply(move: .call, playerKey: "host-key", to: finished)
        finished = try HandRound.apply(move: .fold, playerKey: "ben", to: finished)
        repo.updateHand(finished, on: table)

        XCTAssertTrue(finished.isComplete)
        XCTAssertEqual(table.hand?.handNumber, 1)
        XCTAssertEqual(table.seats.first { $0.playerKey == "host-key" }?.amountDecimal, 21)
        XCTAssertEqual(table.seats.first { $0.playerKey == "ben" }?.amountDecimal, 19)

        try repo.dealNextHand(on: table)

        let next = try XCTUnwrap(table.hand)
        XCTAssertEqual(next.handNumber, 2)
        XCTAssertEqual(next.street, .preflop)
        XCTAssertFalse(next.isComplete)
        XCTAssertTrue(next.board.isEmpty)
        XCTAssertNotEqual(next.id, first.id)
        XCTAssertEqual(next.seat(forPlayerKey: "host-key")?.stackDecimal, 21)
        XCTAssertEqual(next.seat(forPlayerKey: "ben")?.stackDecimal, 19)
    }

    func testChangingTheAnteAppliesToTheNextHandNotTheCurrentOne() throws {
        let repo = TableRepository(context: try makeContext())
        let table = try hostedHeadsUpTable(repo)
        repo.updateAnte(1, on: table)

        let first = try repo.dealHand(on: table)
        XCTAssertEqual(first.anteDecimal, 1)

        repo.updateAnte(2, on: table)
        XCTAssertEqual(table.anteDecimal, 2)
        XCTAssertEqual(table.hand?.anteDecimal, 1, "The hand already being played keeps its ante")

        var finished = try HandRound.apply(move: .call, playerKey: "ben", to: first)
        finished = try HandRound.apply(move: .call, playerKey: "host-key", to: finished)
        finished = try HandRound.apply(move: .fold, playerKey: "ben", to: finished)
        repo.updateHand(finished, on: table)
        try repo.dealNextHand(on: table)

        XCTAssertEqual(table.hand?.anteDecimal, 2)
        XCTAssertEqual(table.hand?.handNumber, 2)
    }

    func testChangingTheAnteBeforeDealingUsesTheNewAmount() throws {
        let repo = TableRepository(context: try makeContext())
        let table = try hostedHeadsUpTable(repo)

        repo.updateAnte(3, on: table)

        let hand = try repo.dealHand(on: table)
        XCTAssertEqual(hand.anteDecimal, 3)
        XCTAssertEqual(table.anteDecimal, 3)
    }

    func testFetchFindsATableById() throws {
        let repo = TableRepository(context: try makeContext())
        let table = try repo.startHostedTable(
            name: "Friday",
            sessionCurrencyCode: "GBP",
            hostDisplayName: "Alex"
        )

        XCTAssertEqual(try repo.fetch(id: table.id)?.inviteCode, table.inviteCode)
        XCTAssertNil(try repo.fetch(id: UUID()))
    }

    func testRemoveDeletesAHostedTableFromThisDevice() async throws {
        let repo = TableRepository(context: try makeContext())
        let table = try repo.startHostedTable(
            name: "Friday",
            sessionCurrencyCode: "GBP",
            hostDisplayName: "Alex"
        )
        let inviteCode = table.inviteCode
        let id = table.id

        XCTAssertEqual(repo.activeInviteCode, inviteCode)

        await repo.remove(table)

        XCTAssertNil(try repo.fetch(id: id))
        XCTAssertNil(try repo.table(inviteCode: inviteCode))
        XCTAssertNil(repo.activeInviteCode)
    }

    func testRemoveForgetsAJoinedTableOnThisDevice() async throws {
        let context = try makeContext()
        let joined = OpenTableModel(
            inviteCode: "JOIN01",
            name: "Friend's table",
            hostDisplayName: "Ben",
            hostPlayerKey: "other-host",
            sessionCurrencyCode: "GBP",
            isHostLocally: false
        )
        context.insert(joined)
        try context.save()

        let repo = TableRepository(context: context)
        repo.makeActive(joined)
        let id = joined.id

        await repo.remove(joined)

        XCTAssertNil(try repo.fetch(id: id))
        XCTAssertNil(repo.activeInviteCode)
    }

    func testGuestsCannotChangeTheAnte() throws {
        let context = try makeContext()
        let joined = OpenTableModel(
            inviteCode: "JOIN01",
            name: "Friend's table",
            hostDisplayName: "Ben",
            hostPlayerKey: "host-key",
            sessionCurrencyCode: "GBP",
            isHostLocally: false,
            anteAmount: "1"
        )
        context.insert(joined)
        try context.save()

        let repo = TableRepository(context: context)
        repo.updateAnte(5, on: joined)

        XCTAssertEqual(joined.anteAmount, "1")
        XCTAssertEqual(joined.anteDecimal, 1)
    }

    private func hostedHeadsUpTable(_ repo: TableRepository) throws -> OpenTableModel {
        try repo.startHostedTable(
            name: "Friday",
            sessionCurrencyCode: "GBP",
            hostDisplayName: "Ana",
            sessionSeats: [
                SessionTableSeat(
                    playerKey: "host-key",
                    playerName: "Ana",
                    handle: nil,
                    amount: 20,
                    isHost: true
                ),
                SessionTableSeat(
                    playerKey: "ben",
                    playerName: "Ben",
                    handle: nil,
                    amount: 20,
                    isHost: false
                )
            ]
        )
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([OpenTableModel.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
