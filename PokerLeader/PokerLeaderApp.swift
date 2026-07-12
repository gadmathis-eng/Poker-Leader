import SwiftUI
import SwiftData

@main
struct PokerLeaderApp: App {
    let container = ModelContainerSetup.makeContainer()
    @State private var router = AppRouter()

    init() {
        SupabaseBootstrap.configureIfPossible()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .modelContainer(container)
                .environment(router)
                .onOpenURL { url in
                    if !router.handleDeepLink(url) {
                        SupabaseAuthManager.shared.handleOpenURL(url)
                    }
                }
                .onAppear {
                    SampleDataSeeder.seedIfNeeded(context: container.mainContext)
                    migratePlayerNicknames(context: container.mainContext)
                    Task {
                        await SupabaseAuthManager.shared.refreshSession()
                        await ExchangeRateService.shared.refreshIfNeeded()
                        if SupabaseAuthManager.shared.isSignedIn {
                            await CloudSyncCoordinator.restoreAccountAndSync(context: container.mainContext)
                        }
                    }
                    if router.currentUserMemberId == nil {
                        let descriptor = FetchDescriptor<MemberModel>(predicate: #Predicate { $0.isCurrentUser })
                        if let me = try? container.mainContext.fetch(descriptor).first {
                            router.currentUserMemberId = me.id
                        }
                    }
                }
        }
    }

    private func migratePlayerNicknames(context: ModelContext) {
        let defaults = UserDefaults.standard

        let descriptor = FetchDescriptor<CircleModel>()
        guard let circles = try? context.fetch(descriptor) else { return }

        let currentUserIds = Set(circles.flatMap(\.members).filter(\.isCurrentUser).map(\.id))
        let existingNonCurrentHandles = Set(
            circles
                .flatMap(\.members)
                .filter { !currentUserIds.contains($0.id) }
                .compactMap { MemberModel.normalizedHandle($0.handle) }
        )

        let storedDisplayName = defaults.string(forKey: "displayName") ?? "Your name"
        let preferredHandle = MemberModel.isPlaceholderName(storedDisplayName)
            ? "@yourname"
            : MemberModel.generatedUniqueHandle(for: storedDisplayName, existingHandles: existingNonCurrentHandles)

        if MemberModel.isPlaceholderHandle(defaults.string(forKey: "playerHandle")) && !MemberModel.isPlaceholderName(storedDisplayName) {
            defaults.set(preferredHandle, forKey: "playerHandle")
        }

        for circle in circles {
            let currentUserIds = Set(circle.members.filter(\.isCurrentUser).map(\.id))
            let memberById = Dictionary(uniqueKeysWithValues: circle.members.map { ($0.id, $0) })

            for member in circle.members where member.isCurrentUser {
                if MemberModel.isPlaceholderHandle(member.handle), !MemberModel.isPlaceholderName(member.displayName) {
                    let existingHandles = Set(
                        circle.members
                            .filter { $0.id != member.id }
                            .compactMap { MemberModel.normalizedHandle($0.handle) }
                    )
                    member.handle = MemberModel.generatedUniqueHandle(for: member.displayName, existingHandles: existingHandles)
                }
            }

            for member in circle.members where member.handle?.isEmpty ?? true {
                if let demoHandle = demoHandle(for: member.displayName) {
                    member.handle = demoHandle
                }
            }

            for session in circle.sessions {
                for player in session.players {
                    if let memberId = player.memberId, let member = memberById[memberId] {
                        let displayName = member.displayName(preferredHandle: currentUserIds.contains(memberId) ? preferredHandle : nil)
                        if player.displayName != displayName {
                            player.displayName = displayName
                        }
                    } else if MemberModel.isPlaceholderName(player.displayName) {
                        player.displayName = preferredHandle
                    }
                }
            }
        }

        try? context.save()
    }

    private func demoHandle(for displayName: String) -> String? {
        switch displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "player a":
            return "@ace"
        case "player l":
            return "@lucky"
        case "player s":
            return "@stacks"
        case "player k":
            return "@king"
        case "alex":
            return "@alexplaysaces"
        case "ben":
            return "@bigblindben"
        case "josh":
            return "@joshjams"
        case "max":
            return "@maxvalue"
        case "dan":
            return "@danger_dan"
        default:
            return nil
        }
    }
}
