import Foundation

enum TableOrderStore {
    private static let key = "tableOrder"

    static func ordered(_ tables: [OpenTableModel]) -> [OpenTableModel] {
        OrderedItemStore.ordered(tables, key: key, id: \.id) {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
    }

    static func save(_ orderedIds: [UUID]) {
        OrderedItemStore.save(orderedIds, key: key)
    }

    static func clearAll() {
        OrderedItemStore.clear(key: key)
    }
}
