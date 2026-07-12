import SwiftUI
import SwiftData

struct LeaderboardView: View {
    @Environment(AppRouter.self) private var router
    @AppStorage("playerHandle") private var playerHandle = "@yourname"
    @Query(sort: \CircleModel.name) private var circles: [CircleModel]
    @State private var selectedCircle: CircleModel?

    private var orderedCircles: [CircleModel] {
        CircleOrderStore.ordered(circles)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Leaderboards")
                        Text("Board")
                            .font(.largeTitle.bold())
                            .foregroundStyle(AppTheme.text)
                        Text("Choose a circle to view its all-time standings.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                    .padding(.horizontal)

                    if orderedCircles.isEmpty {
                        ContentUnavailableView("No circles", systemImage: "trophy")
                            .padding(.top, 40)
                    } else {
                        ForEach(orderedCircles) { circle in
                            let meId = router.currentUserMemberId ?? circle.members.first(where: \.isCurrentUser)?.id
                            let me = circle.members.first { $0.id == meId }
                            let entries = LeaderboardService.entries(for: circle, currentUserMemberId: meId)

                            Button {
                                selectedCircle = circle
                            } label: {
                                BoardCirclePickerRow(
                                    circle: circle,
                                    yourNet: LeaderboardService.yourNet(in: circle, memberId: meId),
                                    currentUserLabel: me?.displayName(preferredHandle: playerHandle) ?? MemberModel.normalizedHandle(playerHandle) ?? "Your name",
                                    leaderName: entries.first?.name,
                                    leaderNet: entries.first?.totalNet,
                                    memberInitials: circle.members.map(\.initial),
                                    lastPlayedText: RelativeDateFormatting.playedAgo(from: circle.lastPlayedAt)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(AppTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedCircle) { circle in
                CircleLeaderboardSheet(circle: circle)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}
