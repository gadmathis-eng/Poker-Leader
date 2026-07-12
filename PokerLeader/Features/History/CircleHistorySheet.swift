import SwiftUI
import SwiftData

struct CircleHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    let circle: CircleModel

    private var settledSessions: [SessionModel] {
        circle.sessions
            .filter { $0.status == .settled }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "\(circle.name) · all time")
                    Text("History")
                        .font(.largeTitle.bold())
                        .foregroundStyle(AppTheme.text)
                    Text("Settled games")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)

                    if settledSessions.isEmpty {
                        ContentUnavailableView("No games yet", systemImage: "clock")
                            .padding(.top, 40)
                    } else {
                        ForEach(settledSessions) { session in
                            NavigationLink {
                                HistorySessionDetailView(session: session, circle: circle)
                            } label: {
                                historyCard(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle(circle.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(AppTheme.muted)
                }
            }
        }
    }

    private func historyCard(session: SessionModel) -> some View {
        let meId = router.currentUserMemberId
        let yourNet = session.players.first { $0.memberId == meId }?.net ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            Text(session.displayTitle(in: circle))
                .font(.headline)
                .foregroundStyle(AppTheme.text)
            Text("\(session.startedAt.formatted(date: .abbreviated, time: .omitted)) · pot \(MoneyFormatting.plain(session.potTotal, currencyCode: session.currencyCode))")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
            HStack {
                MoneyText(amount: yourNet, currencyCode: session.currencyCode)
                Text("you")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                Spacer()
            }
            if let line = session.summaryLine {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .padding()
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.cardBorder))
    }
}

struct HistorySessionDetailView: View {
    let session: SessionModel
    let circle: CircleModel

    private var sortedPlayers: [SessionPlayerModel] {
        session.players.sorted { ($0.net ?? 0) > ($1.net ?? 0) }
    }

    private var winner: SessionPlayerModel? {
        sortedPlayers.first
    }

    private var biggestLoss: SessionPlayerModel? {
        sortedPlayers.last
    }

    private var endedAt: Date {
        session.endedAt ?? session.startedAt
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                summaryGrid
                playersSection
                paymentsSection
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Game stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: circle.name.uppercased())

            Text(session.displayTitle(in: circle))
                .font(.largeTitle.bold())
                .foregroundStyle(AppTheme.text)

            Text("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(endedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)

            if let summaryLine = session.summaryLine {
                Text(summaryLine)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
                    .padding(.top, 4)
            }
        }
    }

    private var summaryGrid: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                statBox(title: "POT", value: MoneyFormatting.plain(session.potTotal, currencyCode: session.currencyCode), tint: AppTheme.text)
                statBox(title: "USERNAMES", value: "\(session.players.count)", tint: AppTheme.text)
            }

            HStack(spacing: 14) {
                statBox(title: "WINNER", value: winner?.displayName ?? "-", tint: AppTheme.positive)
                statBox(title: "BIGGEST LOSS", value: biggestLoss?.displayName ?? "-", tint: AppTheme.negative)
            }
        }
    }

    private var playersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Username stats")

            ForEach(sortedPlayers) { player in
                if let memberId = player.memberId {
                    NavigationLink {
                        PlayerProfileView(memberId: memberId)
                    } label: {
                        playerStatsCard(player, showsProfileLink: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    playerStatsCard(player, showsProfileLink: false)
                }
            }
        }
    }

    private func playerStatsCard(_ player: SessionPlayerModel, showsProfileLink: Bool) -> some View {
        VStack(spacing: 12) {
            HStack {
                PlayerAvatarView(initial: player.initial, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.displayName)
                        .font(.headline)
                        .foregroundStyle(AppTheme.text)
                    Text("\(player.buyInCount)x buy-in")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer()

                MoneyText(amount: player.net ?? 0, currencyCode: session.currencyCode)

                if showsProfileLink {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.muted)
                }
            }

            HStack {
                statPill(title: "IN", amount: player.totalIn)
                statPill(title: "OUT", amount: player.finalOut ?? 0)
            }
        }
        .padding()
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.cardBorder))
    }

    @ViewBuilder
    private var paymentsSection: some View {
        if !session.payments.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Settlements")

                ForEach(session.payments) { payment in
                    HStack {
                        Text("\(payment.fromName) pays \(payment.toName)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.text)
                        Spacer()
                        MoneyText(amount: payment.amount, currencyCode: session.currencyCode, showSign: false)
                    }
                    .padding()
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.cardBorder))
                }
            }
        }
    }

    private func statBox(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(AppTheme.muted)

            Text(value)
                .font(.title3.weight(.heavy))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding()
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.cardBorder))
    }

    private func statPill(title: String, amount: Decimal) -> some View {
        HStack {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppTheme.muted)
            Spacer()
            Text(MoneyFormatting.plain(amount, currencyCode: session.currencyCode))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.background)
        .clipShape(Capsule())
    }
}
