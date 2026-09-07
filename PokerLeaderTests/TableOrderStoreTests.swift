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

final class TableRemovalCopyTests: XCTestCase {
    func testHostedTableUsesDeleteCopy() {
        let table = makeTable(name: "Friday", inviteCode: "AAAAAA", isHostLocally: true)

        XCTAssertEqual(MyTablesSheet.removeActionTitle(for: [table]), "Delete table")
        XCTAssertEqual(MyTablesSheet.removeConfirmationTitle(for: [table]), "Delete this table?")
        XCTAssertTrue(MyTablesSheet.removeConfirmationMessage(for: [table]).contains("closes the table"))
    }

    func testJoinedTableUsesLeaveCopy() {
        let table = makeTable(name: "Friday", inviteCode: "BBBBBB", isHostLocally: false)

        XCTAssertEqual(MyTablesSheet.removeActionTitle(for: [table]), "Leave table")
        XCTAssertEqual(MyTablesSheet.removeConfirmationTitle(for: [table]), "Leave this table?")
        XCTAssertTrue(MyTablesSheet.removeConfirmationMessage(for: [table]).contains("frees your seat"))
    }

    func testMixedTablesUseRemoveCopy() {
        let hosted = makeTable(name: "Host", inviteCode: "AAAAAA", isHostLocally: true)
        let joined = makeTable(name: "Join", inviteCode: "BBBBBB", isHostLocally: false)

        XCTAssertEqual(MyTablesSheet.removeActionTitle(for: [hosted, joined]), "Remove tables")
        XCTAssertEqual(MyTablesSheet.removeConfirmationTitle(for: [hosted, joined]), "Remove these tables?")
    }

    func testSeveralHostedTablesUseDeleteCopy() {
        let first = makeTable(name: "Friday", inviteCode: "AAAAAA", isHostLocally: true)
        let second = makeTable(name: "Sunday", inviteCode: "BBBBBB", isHostLocally: true)

        XCTAssertEqual(MyTablesSheet.removeActionTitle(for: [first, second]), "Delete tables")
        XCTAssertEqual(MyTablesSheet.removeConfirmationTitle(for: [first, second]), "Delete these tables?")
    }

    func testSeveralJoinedTablesUseLeaveCopy() {
        let first = makeTable(name: "Friday", inviteCode: "AAAAAA", isHostLocally: false)
        let second = makeTable(name: "Sunday", inviteCode: "BBBBBB", isHostLocally: false)

        XCTAssertEqual(MyTablesSheet.removeActionTitle(for: [first, second]), "Leave tables")
        XCTAssertEqual(MyTablesSheet.removeConfirmationTitle(for: [first, second]), "Leave these tables?")
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
