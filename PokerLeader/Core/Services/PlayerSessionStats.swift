import Foundation

struct PlayerSessionHighlight: Hashable {
    let session: SessionModel
    let circle: CircleModel
}

enum PlayerSessionStats {
    struct Result {
        let session: SessionModel
        let player: SessionPlayerModel
        let circle: CircleModel
        let convertedNet: Decimal
        let playedAt: Date
    }

    static func results(
        circles: [CircleModel],
        memberIds: Set<UUID>,
        displayName: String? = nil,
        preferredCurrencyCode: String
    ) -> [Result] {
        circles.flatMap { circle in
            circle.sessions
                .filter { $0.status == .settled }
                .compactMap { session in
                    guard let player = session.players.first(where: { player in
                        if let memberId = player.memberId {
                            return memberIds.contains(memberId)
                        }
                        if let displayName {
                            return player.displayName == displayName
                        }
                        return false
                    }) else {
                        return nil
                    }

                    return Result(
                        session: session,
                        player: player,
                        circle: circle,
                        convertedNet: ExchangeRateService.shared.convert(
                            player.net ?? 0,
                            from: session.currencyCode,
                            to: preferredCurrencyCode
                        ),
                        playedAt: session.endedAt ?? session.startedAt
                    )
                }
        }
        .sorted { $0.playedAt > $1.playedAt }
    }

    static func bestNight(in results: [Result]) -> PlayerSessionHighlight? {
        guard let best = results.max(by: compareByNetThenRecency) else { return nil }
        return PlayerSessionHighlight(session: best.session, circle: best.circle)
    }

    static func worstNight(in results: [Result]) -> PlayerSessionHighlight? {
        guard let worst = results.min(by: compareByNetThenRecency) else { return nil }
        return PlayerSessionHighlight(session: worst.session, circle: worst.circle)
    }

    static func lastGame(in results: [Result]) -> PlayerSessionHighlight? {
        guard let latest = results.first else { return nil }
        return PlayerSessionHighlight(session: latest.session, circle: latest.circle)
    }

    static func convertedNetTotal(in results: [Result]) -> Decimal {
        results.reduce(0) { $0 + $1.convertedNet }
    }

    static func bestNightAmount(in results: [Result]) -> Decimal {
        results.map(\.convertedNet).max() ?? 0
    }

    static func worstNightAmount(in results: [Result]) -> Decimal {
        results.map(\.convertedNet).min() ?? 0
    }

    private static func compareByNetThenRecency(_ lhs: Result, _ rhs: Result) -> Bool {
        if lhs.convertedNet != rhs.convertedNet {
            return lhs.convertedNet < rhs.convertedNet
        }
        return lhs.playedAt < rhs.playedAt
    }
}
