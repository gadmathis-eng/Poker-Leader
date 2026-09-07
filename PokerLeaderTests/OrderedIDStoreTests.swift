import XCTest
@testable import PokerLeader

final class OrderedIDStoreTests: XCTestCase {
    private struct Item {
        let id: UUID
        let name: String
        let rank: Int
    }

    func testDefaultsToTheProvidedSort() {
        let items = [
            Item(id: UUID(), name: "B", rank: 2),
            Item(id: UUID(), name: "A", rank: 1)
        ]

        let ordered = OrderedIDStore.ordered(
            items,
            storedIds: [],
            id: \.id,
            newItemsAtStart: false
        ) { $0.name < $1.name }

        XCTAssertEqual(ordered.map(\.name), ["A", "B"])
    }

    func testNewItemsGoLastLikeCircles() {
        let saved = Item(id: UUID(), name: "Saved", rank: 1)
        let newest = Item(id: UUID(), name: "New", rank: 3)

        let ordered = OrderedIDStore.ordered(
            [saved, newest],
            storedIds: [saved.id],
            id: \.id,
            newItemsAtStart: false
        ) { $0.rank > $1.rank }

        XCTAssertEqual(ordered.map(\.name), ["Saved", "New"])
    }

    func testNewItemsGoFirstLikeTables() {
        let saved = Item(id: UUID(), name: "Saved", rank: 1)
        let newest = Item(id: UUID(), name: "New", rank: 3)

        let ordered = OrderedIDStore.ordered(
            [saved, newest],
            storedIds: [saved.id],
            id: \.id,
            newItemsAtStart: true
        ) { $0.rank > $1.rank }

        XCTAssertEqual(ordered.map(\.name), ["New", "Saved"])
    }
}
