import SwiftUI
import SwiftData

struct CirclesHomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @AppStorage("playerHandle") private var playerHandle = "@yourname"
    @AppStorage("preferredCurrencyCode") private var preferredCurrencyCode = CurrencyPreferences.defaultCurrencyCode
    @Query(sort: \CircleModel.name) private var circles: [CircleModel]
    @Query(sort: \AppNotificationModel.createdAt, order: .reverse) private var notifications: [AppNotificationModel]
    @State private var showNewCircle = false
    @State private var showJoinCircle = false
    @State private var showEditCircles = false
    @State private var showNotificationCenter = false
    @State private var rateStatusText = ExchangeRateService.shared.rateStatusText

    private var unreadNotificationCount: Int {
        notifications.filter { !$0.isRead && !$0.isHandled }.count
    }

    private var orderedCircles: [CircleModel] {
        CircleOrderStore.ordered(circles)
    }

    private var allCirclesNet: Decimal {
        orderedCircles.reduce(0) { total, circle in
            total + convertedCurrentUserNet(in: circle)
        }
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.circlesPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pot Master")
                            .font(.largeTitle.bold())
                            .foregroundStyle(AppTheme.text)
                        SectionHeader(title: "Your circles")
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ALL CIRCLES")
                            .font(.caption2.weight(.bold))
                            .tracking(AppTheme.sectionTracking)
                            .foregroundStyle(AppTheme.muted)
                        MoneyText(amount: allCirclesNet, currencyCode: preferredCurrencyCode)
                            .font(.title.weight(.heavy))
                        Text(rateStatusText)
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.cardBorder))
                    .padding(.horizontal)

                    ForEach(orderedCircles) { circle in
                        let meId = router.currentUserMemberId ?? circle.members.first(where: \.isCurrentUser)?.id
                        let me = circle.members.first { $0.id == meId }
                        let isCreator = CircleCreatorStore.isCreator(of: circle.id)
                        CircleCardView(
                            circle: circle,
                            yourNet: LeaderboardService.yourNet(in: circle, memberId: meId),
                            currentUserLabel: me?.displayName(preferredHandle: playerHandle) ?? MemberModel.normalizedHandle(playerHandle) ?? "Your name",
                            memberInitials: circle.members.map(\.initial),
                            lastPlayedText: RelativeDateFormatting.playedAgo(from: circle.lastPlayedAt),
                            showsInviteShare: isCreator
                        )
                        .contentShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        .onTapGesture {
                            router.selectedCircleId = circle.id
                            router.push(.newSession(circle.id))
                        }
                        .contextMenu {
                            Button("View circle") { router.push(.circleDetail(circle.id)) }
                            if isCreator {
                                ShareLink(
                                    item: CircleInviteSharing.url(for: circle),
                                    subject: Text("Join \(circle.name) on Pot Master"),
                                    message: Text(CircleInviteSharing.message(for: circle))
                                ) {
                                    Label("Share invite", systemImage: "square.and.arrow.up")
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    VStack(spacing: 12) {
                        Button { showJoinCircle = true } label: {
                            Label("Join with creator invite", systemImage: "link")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppTheme.card)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        }
                        Button { showNewCircle = true } label: {
                            Label("New circle", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppTheme.card)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        }
                    }
                    .foregroundStyle(AppTheme.text)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(AppTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NotificationCenterButton(unreadCount: unreadNotificationCount) {
                        NotificationRepository(context: context).markAllAsSeen()
                        showNotificationCenter = true
                    }
                    .fixedSize()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEditCircles = true } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.body.weight(.medium))
                            .accessibilityLabel("Edit circles")
                    }
                }
            }
            .navigationDestination(for: AppRoute.self, destination: routeDestination)
            .sheet(isPresented: $showNewCircle) {
                NewCircleSheet()
            }
            .sheet(isPresented: $showJoinCircle, onDismiss: {
                router.pendingInviteCode = nil
            }) {
                JoinCircleSheet(initialInviteCode: router.pendingInviteCode)
            }
            .sheet(isPresented: $showEditCircles) {
                EditCirclesSheet(circles: orderedCircles)
            }
            .sheet(isPresented: $showNotificationCenter) {
                NotificationCenterSheet(
                    notifications: notifications,
                    onRefresh: refreshNotifications
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .onChange(of: router.pendingInviteCode) { _, code in
                if code != nil {
                    showJoinCircle = true
                }
            }
            .onChange(of: router.pendingSettlementSessionId) { _, sessionId in
                if let sessionId {
                    openSettlement(sessionId)
                }
            }
            .onAppear {
                if router.pendingInviteCode != nil {
                    showJoinCircle = true
                }
                if let sessionId = router.pendingSettlementSessionId {
                    openSettlement(sessionId)
                }
                rateStatusText = ExchangeRateService.shared.rateStatusText
                Task {
                    await ExchangeRateService.shared.refreshIfNeeded()
                    rateStatusText = ExchangeRateService.shared.rateStatusText
                    await refreshNotifications()
                }
            }
        }
    }

    private func refreshNotifications() async {
        await CloudSyncCoordinator.syncAll(
            context: context,
            displayName: UserDefaults.standard.string(forKey: "displayName") ?? "Your name",
            playerHandle: UserDefaults.standard.string(forKey: "playerHandle") ?? "@yourname"
        )
    }

    private func openSettlement(_ sessionId: UUID) {
        defer { router.pendingSettlementSessionId = nil }

        guard circles.contains(where: { circle in
            circle.sessions.contains { $0.id == sessionId }
        }) else { return }

        if let circle = circles.first(where: { $0.sessions.contains { $0.id == sessionId } }) {
            router.selectedCircleId = circle.id
        }

        router.push(.settlement(sessionId))
    }

    private func convertedCurrentUserNet(in circle: CircleModel) -> Decimal {
        let memberIds = Set(circle.members.filter(\.isCurrentUser).map(\.id))
        return circle.sessions
            .filter { $0.status == .settled }
            .reduce(0) { total, session in
                let sessionNet = session.players
                    .filter { player in
                        guard let memberId = player.memberId else { return false }
                        return memberIds.contains(memberId)
                    }
                    .reduce(Decimal(0)) { $0 + ($1.net ?? 0) }

                return total + ExchangeRateService.shared.convert(
                    sessionNet,
                    from: session.currencyCode,
                    to: preferredCurrencyCode
                )
            }
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
