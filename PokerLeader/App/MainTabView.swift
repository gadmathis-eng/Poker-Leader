import SwiftData
import SwiftUI

struct MainTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @AppStorage("displayName") private var displayName = "Your name"
    @AppStorage("appAppearance") private var appAppearance = AppAppearancePreference.dark.rawValue
    @AppStorage("playerHandle") private var playerHandle = "@yourname"
    @State private var selectedTab = 0
    @State private var showSignIn = false
    @State private var authManager = SupabaseAuthManager.shared

    private var needsProfileOnboarding: Bool {
        MemberModel.isPlaceholderName(displayName)
            && (!SupabaseBootstrap.isConfigured || authManager.isSignedIn)
    }

    private var needsSignIn: Bool {
        SupabaseBootstrap.isConfigured && !authManager.isSignedIn
    }

    private var appearancePreference: AppAppearancePreference {
        AppAppearancePreference(rawValue: appAppearance) ?? .dark
    }

    private var currentUserTabLabel: String {
        MemberModel.isPlaceholderName(displayName) ? "Your name" : displayName
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            CirclesHomeView()
                .tabItem { Label("Circles", systemImage: "person.3.fill") }
                .tag(0)

            HistoryView()
                .tabItem { Label("History", systemImage: "clock.fill") }
                .tag(1)

            LeaderboardView()
                .tabItem { Label("Board", systemImage: "trophy.fill") }
                .tag(2)

            ProfileSettingsView()
                .tabItem { Label(currentUserTabLabel, systemImage: "person.fill") }
                .tag(3)
        }
        .tint(AppTheme.positive)
        .preferredColorScheme(appearancePreference.colorScheme)
        .sheet(isPresented: .constant(needsProfileOnboarding)) {
            ProfileOnboardingSheet(displayName: $displayName, playerHandle: $playerHandle)
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showSignIn) {
            SignInSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(needsSignIn)
        }
        .task {
            await authManager.refreshSession()
            if needsSignIn && !needsProfileOnboarding {
                showSignIn = true
            } else if authManager.isSignedIn {
                await CloudSyncCoordinator.restoreAccountAndSync(context: context)
                updateRouterCurrentUser()
            }
        }
        .onChange(of: router.pendingSettlementSessionId) { _, sessionId in
            if sessionId != nil {
                selectedTab = 0
            }
        }
        .onChange(of: authManager.isSignedIn) { _, signedIn in
            if signedIn {
                Task {
                    await CloudSyncCoordinator.restoreAccountAndSync(context: context)
                    updateRouterCurrentUser()
                }
            } else {
                selectedTab = 0
                router.popToRoot()
                if SupabaseBootstrap.isConfigured {
                    showSignIn = true
                }
            }
        }
        .onChange(of: needsProfileOnboarding) { _, needsOnboarding in
            if !needsOnboarding && needsSignIn {
                showSignIn = true
            }
        }
    }

    private func updateRouterCurrentUser() {
        let descriptor = FetchDescriptor<MemberModel>(predicate: #Predicate { $0.isCurrentUser })
        if let me = try? context.fetch(descriptor).first {
            router.currentUserMemberId = me.id
        } else {
            router.currentUserMemberId = nil
        }
    }
}
