import Foundation

struct LeaderboardEntry: Identifiable {
    let id: UUID
    let name: String
    let initial: String
    let gamesPlayed: Int
    let totalNet: Decimal
    let streakCount: Int
    let streakType: StreakType
}

enum LeaderboardService {
    static func entries(for circle: CircleModel, currentUserMemberId: UUID?) -> [LeaderboardEntry] {
        let settled = circle.sessions.filter { $0.status == .settled }
        var stats: [UUID: (name: String, initial: String, games: Int, net: Decimal, results: [Bool])] = [:]

        for session in settled {
            for player in session.players {
                let key = player.memberId ?? player.id
                let net = ExchangeRateService.shared.convert(
                    player.net ?? 0,
                    from: session.currencyCode,
                    to: circle.currencyCode
                )
                var entry = stats[key] ?? (player.displayName, player.initial, 0, 0, [])
                entry.games += 1
                entry.net += net
                entry.results.append(net > 0)
                stats[key] = entry
            }
        }

        return stats.map { id, value in
            let streak = computeStreak(from: value.results)
            return LeaderboardEntry(
                id: id,
                name: value.name,
                initial: value.initial,
                gamesPlayed: value.games,
                totalNet: value.net,
                streakCount: streak.count,
                streakType: streak.type
            )
        }
        .sorted { $0.totalNet > $1.totalNet }
    }

    private static func computeStreak(from results: [Bool]) -> (count: Int, type: StreakType) {
        guard let last = results.last else { return (0, .win) }
        var count = 0
        for result in results.reversed() {
            if result == last { count += 1 } else { break }
        }
        return (count, last ? .win : .loss)
    }

    static func yourNet(in circle: CircleModel, memberId: UUID?) -> Decimal {
        guard let memberId else { return 0 }
        return circle.sessions
            .filter { $0.status == .settled }
            .reduce(0) { total, session in
                let sessionNet = session.players
                    .filter { $0.memberId == memberId }
                    .reduce(Decimal(0)) { $0 + ($1.net ?? 0) }

                return total + ExchangeRateService.shared.convert(
                    sessionNet,
                    from: session.currencyCode,
                    to: circle.currencyCode
                )
            }
    }
}
