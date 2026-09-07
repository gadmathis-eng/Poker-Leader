import Foundation

enum OrderedIDStore {
    static func ordered<Item>(
        _ items: [Item],
        storedIds: [UUID],
        id: KeyPath<Item, UUID>,
        newItemsAtStart: Bool,
        sortedBy areInIncreasingOrder: (Item, Item) -> Bool
    ) -> [Item] {
        guard !storedIds.isEmpty else {
            return items.sorted(by: areInIncreasingOrder)
        }

        let itemById = Dictionary(uniqueKeysWithValues: items.map { ($0[keyPath: id], $0) })
        let orderedStoredItems = storedIds.compactMap { itemById[$0] }
        let orderedStoredIds = Set(orderedStoredItems.map { $0[keyPath: id] })
        let newItems = items
            .filter { !orderedStoredIds.contains($0[keyPath: id]) }
            .sorted(by: areInIncreasingOrder)

        return newItemsAtStart ? newItems + orderedStoredItems : orderedStoredItems + newItems
    }

    static func load(from defaults: UserDefaults = .standard, key: String) -> [UUID] {
        defaults
            .stringArray(forKey: key)?
            .compactMap(UUID.init(uuidString:)) ?? []
    }

    static func save(_ orderedIds: [UUID], to defaults: UserDefaults = .standard, key: String) {
        defaults.set(orderedIds.map(\.uuidString), forKey: key)
    }

    static func removing(_ id: UUID, from defaults: UserDefaults = .standard, key: String) {
        save(load(from: defaults, key: key).filter { $0 != id }, to: defaults, key: key)
    }

    static func clear(from defaults: UserDefaults = .standard, key: String) {
        defaults.removeObject(forKey: key)
    }
}
