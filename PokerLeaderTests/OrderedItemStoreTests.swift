import XCTest
@testable import PokerLeader

final class OrderedItemStoreTests: XCTestCase {
    private struct Item {
        let id: UUID
        let name: String
    }

    private var key: String!

    override func setUp() {
        super.setUp()
        key = "test.orderedItemStore.\(UUID().uuidString)"
    }

    override func tearDown() {
        OrderedItemStore.clear(key: key)
        key = nil
        super.tearDown()
    }

    func testEmptyStoreSortsByTheFallback() {
        let zebra = Item(id: UUID(), name: "Zebra")
        let apple = Item(id: UUID(), name: "Apple")

        let ordered = OrderedItemStore.ordered([zebra, apple], key: key, id: \.id) {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        XCTAssertEqual(ordered.map(\.name), ["Apple", "Zebra"])
    }

    func testSavedOrderIsAppliedAndUnknownIdsAreSkipped() {
        let first = Item(id: UUID(), name: "First")
        let second = Item(id: UUID(), name: "Second")
        let missing = UUID()

        OrderedItemStore.save([second.id, missing, first.id], key: key)

        let ordered = OrderedItemStore.ordered([first, second], key: key, id: \.id) {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        XCTAssertEqual(ordered.map(\.id), [second.id, first.id])
    }

    func testNewItemsAreAppendedAfterTheSavedOrder() {
        let first = Item(id: UUID(), name: "First")
        let second = Item(id: UUID(), name: "Second")
        let newer = Item(id: UUID(), name: "Alpha")

        OrderedItemStore.save([second.id, first.id], key: key)

        let ordered = OrderedItemStore.ordered([newer, first, second], key: key, id: \.id) {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        XCTAssertEqual(ordered.map(\.id), [second.id, first.id, newer.id])
    }

    func testCircleOrderStoreStillUsesTheOriginalDefaultsKey() {
        UserDefaults.standard.removeObject(forKey: "circleOrder")
        defer { UserDefaults.standard.removeObject(forKey: "circleOrder") }

        let first = UUID()
        let second = UUID()
        CircleOrderStore.save([first, second])

        XCTAssertEqual(
            UserDefaults.standard.stringArray(forKey: "circleOrder"),
            [first.uuidString, second.uuidString]
        )

        CircleOrderStore.clearAll()
        XCTAssertNil(UserDefaults.standard.stringArray(forKey: "circleOrder"))
    }
}

@MainActor
final class TableOrderStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TableOrderStore.clearAll()
    }

    override func tearDown() {
        TableOrderStore.clearAll()
        super.tearDown()
    }

    func testFallbackOrderPutsTheMostRecentlyUpdatedTableFirst() {
        let older = table(named: "Older", inviteCode: "OLD001", updatedAt: Date(timeIntervalSince1970: 1))
        let newer = table(named: "Newer", inviteCode: "NEW001", updatedAt: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(TableOrderStore.ordered([older, newer]).map(\.id), [newer.id, older.id])
    }

    func testSavedOrderWinsAndNewTablesAreAppended() {
        let first = table(named: "First", inviteCode: "AAA111", updatedAt: Date(timeIntervalSince1970: 1))
        let second = table(named: "Second", inviteCode: "BBB222", updatedAt: Date(timeIntervalSince1970: 2))
        let newest = table(named: "Newest", inviteCode: "CCC333", updatedAt: Date(timeIntervalSince1970: 3))

        TableOrderStore.save([first.id, second.id])

        XCTAssertEqual(
            TableOrderStore.ordered([newest, second, first]).map(\.id),
            [first.id, second.id, newest.id]
        )
    }

    private func table(named name: String, inviteCode: String, updatedAt: Date) -> OpenTableModel {
        OpenTableModel(
            inviteCode: inviteCode,
            name: name,
            hostDisplayName: "Alex",
            hostPlayerKey: "host-key",
            sessionCurrencyCode: "GBP",
            isHostLocally: true,
            updatedAt: updatedAt
        )
    }
}
