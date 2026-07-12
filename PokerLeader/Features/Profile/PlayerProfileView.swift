import SwiftUI
import SwiftData

struct PlayerProfileView: View {
    @Environment(AppRouter.self) private var router
    @AppStorage("playerHandle") private var playerHandle = "@yourname"
    let memberId: UUID
    @Query private var circles: [CircleModel]

    var body: some View {
        let member = circles.flatMap(\.members).first { $0.id == memberId }
        let circle = circles.first { $0.members.contains { $0.id == memberId } }
        let playerSessionResults = circle.map {
            PlayerSessionStats.results(
                circles: [$0],
                memberIds: [memberId],
                preferredCurrencyCode: $0.currencyCode
            )
        } ?? []
        let playerSessions = playerSessionResults.map(\.player)
        let opponentName = mostCommonOpponentName(
            in: playerSessionResults.map { ($0.session, $0.player) },
            fallback: "Opponents"
        )
        let sessionsWon = playerSessionResults.filter { $0.convertedNet > 0 }.count
        let sessionsLost = playerSessionResults.filter { $0.convertedNet <= 0 }.count
        let total = PlayerSessionStats.convertedNetTotal(in: playerSessionResults)
        let bestNight = PlayerSessionStats.bestNightAmount(in: playerSessionResults)
        let worstNight = PlayerSessionStats.worstNightAmount(in: playerSessionResults)
        let bestNightHighlight = PlayerSessionStats.bestNight(in: playerSessionResults)
        let worstNightHighlight = PlayerSessionStats.worstNight(in: playerSessionResults)

        ScrollView {
            if let member, let circle {
                let memberDisplayName = member.displayName(preferredHandle: playerHandle)
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        PlayerAvatarView(initial: member.initial, size: 72)
                        VStack(alignment: .leading) {
                            Text(memberDisplayName)
                                .font(.title.bold())
                            if let handle = MemberModel.normalizedHandle(member.handle) {
                                Text(handle)
                                    .foregroundStyle(AppTheme.muted)
                            }
                            Text(circle.name)
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                    .foregroundStyle(AppTheme.text)

                    let entries = LeaderboardService.entries(for: circle, currentUserMemberId: memberId)
                    let stats = entries.first { $0.id == memberId }

                    sessionsWonCard(
                        playerName: memberDisplayName,
                        opponentName: opponentName,
                        sessionsWon: sessionsWon,
                        sessionsLost: sessionsLost
                    )

                    HStack {
                        statBox(
                            title: "TOTAL",
                            value: MoneyFormatting.format(total, currencyCode: circle.currencyCode),
                            tint: total < 0 ? AppTheme.negative : AppTheme.positive
                        )
                        statBox(title: "GAMES", value: "\(playerSessions.count)", tint: AppTheme.text)
                    }

                    HStack {
                        statBoxLink(
                            title: "BEST NIGHT",
                            value: MoneyFormatting.format(bestNight, currencyCode: circle.currencyCode),
                            tint: AppTheme.positive,
                            highlight: bestNightHighlight
                        )
                        statBoxLink(
                            title: "WORST NIGHT",
                            value: MoneyFormatting.format(worstNight, currencyCode: circle.currencyCode),
                            tint: worstNight < 0 ? AppTheme.negative : AppTheme.text,
                            highlight: worstNightHighlight
                        )
                    }

                    SectionHeader(title: "Badges")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(BadgeService.badges(for: stats), id: \.id) { badge in
                                Text(badge.title)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(AppTheme.card)
                                    .clipShape(Capsule())
                                    .foregroundStyle(AppTheme.text)
                            }
                        }
                    }

                    if let rival = circle.members.first(where: { $0.initial == "B" }) {
                        Button {
                            router.push(.headToHead(memberId, rival.id))
                        } label: {
                            Text("View rivalry vs \(rival.displayName)")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppTheme.card)
                                .foregroundStyle(AppTheme.text)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        }
                    }
                }
                .padding()
            } else {
                ContentUnavailableView("Username not found", systemImage: "person")
            }
        }
        .background(AppTheme.background)
    }

    private func mostCommonOpponentName(
        in results: [(session: SessionModel, player: SessionPlayerModel)],
        fallback: String
    ) -> String {
        var counts: [String: Int] = [:]

        for result in results {
            for player in result.session.players where player.memberId != memberId {
                counts[player.displayName, default: 0] += 1
            }
        }

        return counts.max { $0.value < $1.value }?.key ?? fallback
    }

    private func sessionsWonCard(
        playerName: String,
        opponentName: String,
        sessionsWon: Int,
        sessionsLost: Int
    ) -> some View {
        let totalSessions = sessionsWon + sessionsLost
        let winShare = totalSessions == 0 ? 0.5 : CGFloat(sessionsWon) / CGFloat(totalSessions)

        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Sessions won")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.text)

                Spacer()

                Text("\(sessionsWon) - \(sessionsLost)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
            }

            GeometryReader { proxy in
                let greenWidth = max(proxy.size.width * winShare - 3, 0)
                let redWidth = max(proxy.size.width * (1 - winShare) - 3, 0)

                HStack(spacing: 6) {
                    Capsule()
                        .fill(AppTheme.positive)
                        .frame(width: greenWidth)
                    Capsule()
                        .fill(AppTheme.negative)
                        .frame(width: redWidth)
                }
            }
            .frame(height: 20)

            HStack {
                Text("\(playerName) \(sessionsWon)")
                Spacer()
                Text("\(opponentName) \(sessionsLost)")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppTheme.muted)
        }
        .padding(28)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }

    private func statBoxLink(
        title: String,
        value: String,
        tint: Color,
        highlight: PlayerSessionHighlight?
    ) -> some View {
        Group {
            if let highlight {
                NavigationLink {
                    HistorySessionDetailView(session: highlight.session, circle: highlight.circle)
                } label: {
                    statBox(title: title, value: value, tint: tint)
                }
                .buttonStyle(.plain)
            } else {
                statBox(title: title, value: value, tint: tint)
            }
        }
    }

    private func statBox(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(AppTheme.muted)
            Text(value)
                .font(.title3.weight(.heavy))
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding()
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }
}
