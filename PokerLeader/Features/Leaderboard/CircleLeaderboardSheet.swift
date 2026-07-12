import SwiftUI
import SwiftData

struct CircleLeaderboardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    let circle: CircleModel

    @State private var profilePath = NavigationPath()

    private var meId: UUID? {
        router.currentUserMemberId ?? circle.members.first(where: \.isCurrentUser)?.id
    }

    private var entries: [LeaderboardEntry] {
        LeaderboardService.entries(for: circle, currentUserMemberId: meId)
    }

    var body: some View {
        NavigationStack(path: $profilePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "\(circle.name) · all time")
                    Text("Leaderboard")
                        .font(.largeTitle.bold())
                        .foregroundStyle(AppTheme.text)
                    Text("Net")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)

                    if let top = entries.first {
                        houseFavouriteCard(top)
                    }

                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            profilePath.append(entry.id)
                        } label: {
                            HStack {
                                Text("\(index + 1)")
                                PlayerAvatarView(initial: entry.initial, size: 32)
                                Text(entry.name)
                                Spacer()
                                MoneyText(amount: entry.totalNet, currencyCode: circle.currencyCode)
                            }
                            .foregroundStyle(AppTheme.text)
                            .padding()
                            .background(AppTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        }
                        .buttonStyle(.plain)
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
            .navigationDestination(for: UUID.self) { memberId in
                PlayerProfileView(memberId: memberId)
            }
        }
    }

    @ViewBuilder
    private func houseFavouriteCard(_ top: LeaderboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOUSE FAVOURITE")
                .font(.caption2.weight(.bold))
                .tracking(AppTheme.sectionTracking)
                .foregroundStyle(AppTheme.gold)
            HStack {
                PlayerAvatarView(initial: top.initial, size: 56)
                Text(top.name)
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.text)
                Spacer()
                MoneyText(amount: top.totalNet, currencyCode: circle.currencyCode)
            }
        }
        .padding()
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.cardBorder)
        )
    }
}
