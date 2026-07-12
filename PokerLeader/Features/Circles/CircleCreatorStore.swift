import Foundation

enum CircleCreatorStore {
    private static let key = "createdCircleIds"

    static func markCreator(_ circleId: UUID) {
        var ids = createdCircleIds
        ids.insert(circleId)
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: key)
    }

    static func isCreator(of circleId: UUID) -> Bool {
        createdCircleIds.contains(circleId)
    }

    static func unmarkCreator(_ circleId: UUID) {
        var ids = createdCircleIds
        ids.remove(circleId)
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: key)
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static var createdCircleIds: Set<UUID> {
        let strings = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(strings.compactMap(UUID.init(uuidString:)))
    }
}
