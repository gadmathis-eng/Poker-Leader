import Foundation

enum DeletedCirclesStore {
    private static let key = "deletedCircleIds"

    static func markDeleted(_ circleId: UUID) {
        var ids = deletedIds
        ids.insert(circleId)
        save(ids)
    }

    static func unmarkDeleted(_ circleId: UUID) {
        var ids = deletedIds
        ids.remove(circleId)
        save(ids)
    }

    static var deletedIds: Set<UUID> {
        let strings = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(strings.compactMap(UUID.init(uuidString:)))
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func save(_ ids: Set<UUID>) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: key)
    }
}
