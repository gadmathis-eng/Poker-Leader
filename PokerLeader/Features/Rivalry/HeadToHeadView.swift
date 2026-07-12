import SwiftUI
import SwiftData

struct HeadToHeadView: View {
    let memberAId: UUID
    let memberBId: UUID
    @Query private var circles: [CircleModel]

    private var memberA: MemberModel? {
        circles.flatMap(\.members).first { $0.id == memberAId }
    }

    private var memberB: MemberModel? {
        circles.flatMap(\.members).first { $0.id == memberBId }
    }

    private var sharedCircle: CircleModel? {
        circles.first { circle in
            circle.members.contains { $0.id == memberAId } &&
            circle.members.contains { $0.id == memberBId }
        }
    }

    private var stats: HeadToHeadStats? {
        guard
            let sharedCircle,
            let memberA,
            let memberB
        else {
            return nil
        }

        return HeadToHeadService.stats(
            circle: sharedCircle,
            memberAId: memberAId,
            memberAName: memberA.displayName,
            memberBId: memberBId,
            memberBName: memberB.displayName
        )
    }

    var body: some View {
        ScrollView {
            if let memberA, let memberB, let stats {
                rivalryContent(memberA: memberA, memberB: memberB, stats: stats)
            } else if memberA != nil, memberB != nil {
                ContentUnavailableView("No shared games yet", systemImage: "person.2")
                    .padding(.top, 40)
            } else {
                ContentUnavailableView("Players not found", systemImage: "person.2")
            }
        }
        .background(AppTheme.background)
        .navigationTitle("")
    }

    private func rivalryContent(memberA: MemberModel, memberB: MemberModel, stats: HeadToHeadStats) -> some View {
        VStack(spacing: 20) {
            SectionHeader(title: "Head-to-head")
            Text("Rivalry")
                .font(.title.bold())
                .foregroundStyle(AppTheme.text)

            HStack(spacing: 24) {
                PlayerAvatarView(initial: memberA.initial, size: 64)
                Text("vs")
                PlayerAvatarView(initial: memberB.initial, size: 64)
            }

            Text("\(stats.leaderName) leads the rivalry")
                .font(.headline)
                .foregroundStyle(AppTheme.gold)
                .multilineTextAlignment(.center)

            Text("\(MoneyFormatting.format(stats.leaderNet, currencyCode: stats.currencyCode)) all-time, head to head")
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)

            Text("Sessions won  \(stats.leaderSessionWins) — \(stats.trailingSessionWins)")
                .foregroundStyle(AppTheme.text)

            Text("\(stats.sharedGames) shared games")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)

            VStack(alignment: .leading, spacing: 8) {
                Text("BIGGEST WIN")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
                Text(MoneyFormatting.format(stats.biggestLeaderWin, currencyCode: stats.currencyCode))
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.positive)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
        .padding()
    }
}
