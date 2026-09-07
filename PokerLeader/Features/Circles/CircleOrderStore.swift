import Foundation

enum CircleOrderStore {
    private static let key = "circleOrder"

    static func ordered(_ circles: [CircleModel]) -> [CircleModel] {
        OrderedIDStore.ordered(
            circles,
            storedIds: load(),
            id: \.id,
            newItemsAtStart: false
        ) { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func save(_ orderedIds: [UUID]) {
        OrderedIDStore.save(orderedIds, key: key)
    }

    static func clearAll() {
        OrderedIDStore.clear(key: key)
    }

    private static func load() -> [UUID] {
        OrderedIDStore.load(key: key)
    }
}
