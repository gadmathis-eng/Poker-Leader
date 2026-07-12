import Foundation

enum CircleOrderStore {
    private static let key = "circleOrder"

    static func ordered(_ circles: [CircleModel]) -> [CircleModel] {
        let storedIds = load()
        guard !storedIds.isEmpty else {
            return circles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        let circleById = Dictionary(uniqueKeysWithValues: circles.map { ($0.id, $0) })
        let orderedStoredCircles = storedIds.compactMap { circleById[$0] }
        let orderedStoredIds = Set(orderedStoredCircles.map(\.id))
        let newCircles = circles
            .filter { !orderedStoredIds.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return orderedStoredCircles + newCircles
    }

    static func save(_ orderedIds: [UUID]) {
        UserDefaults.standard.set(orderedIds.map(\.uuidString), forKey: key)
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func load() -> [UUID] {
        UserDefaults.standard
            .stringArray(forKey: key)?
            .compactMap(UUID.init(uuidString:)) ?? []
    }
}
