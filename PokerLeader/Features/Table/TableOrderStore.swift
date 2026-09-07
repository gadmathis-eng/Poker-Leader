import Foundation

enum TableOrderStore {
    private static let key = "tableOrder"

    static var defaults = UserDefaults.standard

    static func ordered(_ tables: [OpenTableModel]) -> [OpenTableModel] {
        let storedIds = load()
        guard !storedIds.isEmpty else {
            return tables.sorted { $0.updatedAt > $1.updatedAt }
        }

        let tableById = Dictionary(uniqueKeysWithValues: tables.map { ($0.id, $0) })
        let orderedStoredTables = storedIds.compactMap { tableById[$0] }
        let orderedStoredIds = Set(orderedStoredTables.map(\.id))
        let newTables = tables
            .filter { !orderedStoredIds.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }

        return newTables + orderedStoredTables
    }

    static func save(_ orderedIds: [UUID]) {
        defaults.set(orderedIds.map(\.uuidString), forKey: key)
    }

    static func removing(_ id: UUID) {
        save(load().filter { $0 != id })
    }

    static func clearAll() {
        defaults.removeObject(forKey: key)
    }

    static func load() -> [UUID] {
        defaults
            .stringArray(forKey: key)?
            .compactMap(UUID.init(uuidString:)) ?? []
    }
}

