import Foundation

struct PlayerBadge: Identifiable, Hashable {
    let id: String
    let title: String
}

enum BadgeService {
    static func badges(for entry: LeaderboardEntry?) -> [PlayerBadge] {
        guard let entry else { return [] }
        var result: [PlayerBadge] = []
        if entry.gamesPlayed >= 20 {
            result.append(PlayerBadge(id: "shark", title: "Table Shark"))
        }
        if entry.totalNet >= 300 {
            result.append(PlayerBadge(id: "favourite", title: "House Favourite"))
        }
        if entry.streakType == .win && entry.streakCount >= 3 {
            result.append(PlayerBadge(id: "comeback", title: "Comeback King"))
        }
        if entry.totalNet > 0 && entry.gamesPlayed >= 10 && entry.streakCount <= 1 {
            result.append(PlayerBadge(id: "silent", title: "Silent Assassin"))
        }
        return result
    }
}
