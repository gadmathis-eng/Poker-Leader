import Foundation

enum OrderedItemStore {
    static func ordered<Item>(
        _ items: [Item],
        key: String,
        id: KeyPath<Item, UUID>,
        by areInIncreasingOrder: (Item, Item) -> Bool
    ) -> [Item] {
        let storedIds = load(key: key)
        guard !storedIds.isEmpty else {
            return items.sorted(by: areInIncreasingOrder)
        }

        let itemById = Dictionary(uniqueKeysWithValues: items.map { ($0[keyPath: id], $0) })
        let orderedStoredItems = storedIds.compactMap { itemById[$0] }
        let orderedStoredIds = Set(orderedStoredItems.map { $0[keyPath: id] })
        let newItems = items
            .filter { !orderedStoredIds.contains($0[keyPath: id]) }
            .sorted(by: areInIncreasingOrder)

        return orderedStoredItems + newItems
    }

    static func save(_ orderedIds: [UUID], key: String) {
        UserDefaults.standard.set(orderedIds.map(\.uuidString), forKey: key)
    }

    static func clear(key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func load(key: String) -> [UUID] {
        UserDefaults.standard
            .stringArray(forKey: key)?
            .compactMap(UUID.init(uuidString:)) ?? []
    }
}
