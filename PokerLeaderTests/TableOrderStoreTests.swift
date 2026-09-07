import XCTest
@testable import PokerLeader

final class TableOrderStoreTests: XCTestCase {
    private let suiteName = "TableOrderStoreTests-\(UUID().uuidString)"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        TableOrderStore.defaults = defaults
    }

    override func tearDown() {
        TableOrderStore.clearAll()
        TableOrderStore.defaults = .standard
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsToNewestFirst() {
        let older = makeTable(name: "Older", inviteCode: "AAAAAA", updatedAt: Date(timeIntervalSince1970: 1))
        let newer = makeTable(name: "Newer", inviteCode: "BBBBBB", updatedAt: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(TableOrderStore.ordered([older, newer]).map(\.name), ["Newer", "Older"])
    }

    func testSavedOrderWinsOverRecency() {
        let friday = makeTable(name: "Friday", inviteCode: "AAAAAA", updatedAt: Date(timeIntervalSince1970: 2))
        let sunday = makeTable(name: "Sunday", inviteCode: "BBBBBB", updatedAt: Date(timeIntervalSince1970: 1))

        TableOrderStore.save([sunday.id, friday.id])

        XCTAssertEqual(TableOrderStore.ordered([friday, sunday]).map(\.name), ["Sunday", "Friday"])
    }

    func testNewTablesSitInFrontOfASavedOrder() {
        let saved = makeTable(name: "Saved", inviteCode: "AAAAAA", updatedAt: Date(timeIntervalSince1970: 1))
        let newest = makeTable(name: "New", inviteCode: "BBBBBB", updatedAt: Date(timeIntervalSince1970: 3))
        let olderNew = makeTable(name: "Also new", inviteCode: "CCCCCC", updatedAt: Date(timeIntervalSince1970: 2))

        TableOrderStore.save([saved.id])

        XCTAssertEqual(
            TableOrderStore.ordered([saved, olderNew, newest]).map(\.name),
            ["New", "Also new", "Saved"]
        )
    }

    func testRemovingDropsATableFromTheSavedOrder() {
        let keep = makeTable(name: "Keep", inviteCode: "AAAAAA", updatedAt: .now)
        let drop = makeTable(name: "Drop", inviteCode: "BBBBBB", updatedAt: .now)

        TableOrderStore.save([drop.id, keep.id])
        TableOrderStore.removing(drop.id)

        XCTAssertEqual(TableOrderStore.load(), [keep.id])
        XCTAssertEqual(TableOrderStore.ordered([keep]).map(\.name), ["Keep"])
    }

    func testClearAllRestoresRecencyOrder() {
        let older = makeTable(name: "Older", inviteCode: "AAAAAA", updatedAt: Date(timeIntervalSince1970: 1))
        let newer = makeTable(name: "Newer", inviteCode: "BBBBBB", updatedAt: Date(timeIntervalSince1970: 2))

        TableOrderStore.save([older.id, newer.id])
        TableOrderStore.clearAll()

        XCTAssertEqual(TableOrderStore.ordered([older, newer]).map(\.name), ["Newer", "Older"])
    }
}

private func makeTable(
    name: String,
    inviteCode: String,
    updatedAt: Date = .now,
    isHostLocally: Bool = true
) -> OpenTableModel {
    OpenTableModel(
        inviteCode: inviteCode,
        name: name,
        hostDisplayName: "Alex",
        hostPlayerKey: "host",
        sessionCurrencyCode: "USD",
        isHostLocally: isHostLocally,
        updatedAt: updatedAt
    )
}
