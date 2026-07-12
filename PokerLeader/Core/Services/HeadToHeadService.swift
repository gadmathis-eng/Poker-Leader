import Foundation

struct HeadToHeadStats {
    let currencyCode: String
    let sharedGames: Int
    let leaderId: UUID
    let leaderName: String
    let trailingName: String
    let leaderNet: Decimal
    let leaderSessionWins: Int
    let trailingSessionWins: Int
    let biggestLeaderWin: Decimal
}

enum HeadToHeadService {
    static func stats(
        circle: CircleModel,
        memberAId: UUID,
        memberAName: String,
        memberBId: UUID,
        memberBName: String
    ) -> HeadToHeadStats? {
        let matchups = circle.sessions
            .filter { $0.status == .settled }
            .compactMap { session -> (netA: Decimal, netB: Decimal)? in
                guard
                    let playerA = session.players.first(where: { $0.memberId == memberAId }),
                    let playerB = session.players.first(where: { $0.memberId == memberBId })
                else {
                    return nil
                }

                return (
                    netA: ExchangeRateService.shared.convert(
                        playerA.net ?? 0,
                        from: session.currencyCode,
                        to: circle.currencyCode
                    ),
                    netB: ExchangeRateService.shared.convert(
                        playerB.net ?? 0,
                        from: session.currencyCode,
                        to: circle.currencyCode
                    )
                )
            }

        guard !matchups.isEmpty else { return nil }

        var leaderSessionWins = 0
        var trailingSessionWins = 0
        var headToHeadNetForA: Decimal = 0
        var biggestMargin: Decimal = 0

        for matchup in matchups {
            let margin = matchup.netA - matchup.netB
            headToHeadNetForA += margin

            if margin > 0 {
                leaderSessionWins += 1
                biggestMargin = max(biggestMargin, margin)
            } else if margin < 0 {
                trailingSessionWins += 1
            }
        }

        let aLeads = headToHeadNetForA >= 0
        let leaderId = aLeads ? memberAId : memberBId
        let leaderName = aLeads ? memberAName : memberBName
        let trailingName = aLeads ? memberBName : memberAName
        let leaderNet = abs(headToHeadNetForA)
        let winsForLeader = aLeads ? leaderSessionWins : trailingSessionWins
        let winsForTrailing = aLeads ? trailingSessionWins : leaderSessionWins

        if !aLeads {
            biggestMargin = matchups.map { $0.netB - $0.netA }.max() ?? 0
        }

        return HeadToHeadStats(
            currencyCode: circle.currencyCode,
            sharedGames: matchups.count,
            leaderId: leaderId,
            leaderName: leaderName,
            trailingName: trailingName,
            leaderNet: leaderNet,
            leaderSessionWins: winsForLeader,
            trailingSessionWins: winsForTrailing,
            biggestLeaderWin: max(biggestMargin, 0)
        )
    }
}
