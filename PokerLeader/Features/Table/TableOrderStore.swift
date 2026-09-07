import Foundation

enum TableOrderStore {
    private static let key = "tableOrder"

    static var defaults = UserDefaults.standard

    static func ordered(_ tables: [OpenTableModel]) -> [OpenTableModel] {
        OrderedIDStore.ordered(
            tables,
            storedIds: load(),
            id: \.id,
            newItemsAtStart: true
        ) { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
    }

    static func save(_ orderedIds: [UUID]) {
        OrderedIDStore.save(orderedIds, to: defaults, key: key)
    }

    static func removing(_ id: UUID) {
        OrderedIDStore.removing(id, from: defaults, key: key)
    }

    static func clearAll() {
        OrderedIDStore.clear(from: defaults, key: key)
    }

    static func load() -> [UUID] {
        OrderedIDStore.load(from: defaults, key: key)
    }
}
