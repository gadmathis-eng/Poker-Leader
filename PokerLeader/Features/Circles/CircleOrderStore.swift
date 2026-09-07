import Foundation

enum CircleOrderStore {
    private static let key = "circleOrder"

    static func ordered(_ circles: [CircleModel]) -> [CircleModel] {
        OrderedItemStore.ordered(circles, key: key, id: \.id) {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func save(_ orderedIds: [UUID]) {
        OrderedItemStore.save(orderedIds, key: key)
    }

    static func clearAll() {
        OrderedItemStore.clear(key: key)
    }
}
