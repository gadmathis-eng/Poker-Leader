import SwiftData
import SwiftUI

struct TableView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \CircleModel.name) private var circles: [CircleModel]
    @State private var tablePath = NavigationPath()

    private var orderedCircles: [CircleModel] {
        CircleOrderStore.ordered(circles)
    }

    var body: some View {
        NavigationStack(path: $tablePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Live poker")
                        Text("Table")
                            .font(.largeTitle.bold())
                            .foregroundStyle(AppTheme.text)
                        Text("Your circles at the table.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                    .padding(.horizontal)

                    if orderedCircles.isEmpty {
                        emptyState
                    } else {
                        ForEach(orderedCircles) { circle in
                            let liveSession = circle.sessions.first { $0.status == .live }
                            CircleOvalTableView(circle: circle, liveSession: liveSession)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    router.selectedCircleId = circle.id
                                    if let liveSession {
                                        tablePath.append(AppRoute.liveTable(liveSession.id))
                                    } else {
                                        tablePath.append(AppRoute.newSession(circle.id))
                                    }
                                }
                                .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(AppTheme.background)
            .navigationDestination(for: AppRoute.self, destination: routeDestination)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image("PokerTableIcon")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 56, height: 56)

            Text("No circles yet")
                .font(.headline)
                .foregroundStyle(AppTheme.text)

            Text("Create or join a circle to see oval tables with circle names here.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.cardBorder)
        )
        .padding(.horizontal)
    }

    @ViewBuilder
    private func routeDestination(_ route: AppRoute) -> some View {
        switch route {
        case .circleDetail(let id): CircleDetailView(circleId: id)
        case .newSession(let id): NewSessionView(circleId: id)
        case .liveTable(let id): LiveTableView(sessionId: id)
        case .finalStacks(let id): FinalStacksView(sessionId: id)
        case .confirmation(let id): ConfirmationView(sessionId: id)
        case .settlement(let id): SettlementResultsView(sessionId: id)
        case .shareSettlement(let id): ShareSettlementView(sessionId: id)
        case .playerProfile(let id): PlayerProfileView(memberId: id)
        case .headToHead(let a, let b): HeadToHeadView(memberAId: a, memberBId: b)
        }
    }
}
