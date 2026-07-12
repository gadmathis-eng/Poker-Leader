import SwiftData
import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case profile = "Profile"
    case currency = "Currency"
    case appearance = "Appearance"

    var id: String { rawValue }
}

struct ProfileSettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("displayName") private var displayName = "Your name"
    @AppStorage("playerHandle") private var playerHandle = "@yourname"
    @AppStorage("countryCode") private var countryCode = ""
    @AppStorage("preferredCurrencyCode") private var preferredCurrencyCode = CurrencyPreferences.defaultCurrencyCode
    @State private var showProfileControls = false
    @State private var settingsInitialTab: SettingsTab = .profile
    @State private var showAddFriend = false
    @State private var showSignIn = false
    @State private var authManager = SupabaseAuthManager.shared
    @State private var rateStatusText = ExchangeRateService.shared.rateStatusText
    @Query private var circles: [CircleModel]
    @Query(sort: \FriendRequestModel.createdAt, order: .reverse) private var friendRequests: [FriendRequestModel]

    private var currentMember: MemberModel? {
        circles.flatMap(\.members).first(where: \.isCurrentUser)
    }

    private var profileDisplayName: String {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if MemberModel.isPlaceholderName(trimmedName), let profileHandle {
            return profileHandle
        }
        return trimmedName.isEmpty ? currentMember?.displayName(preferredHandle: playerHandle) ?? "Your name" : trimmedName
    }

    private var profileHandle: String? {
        currentMember?.handle ?? MemberModel.normalizedHandle(playerHandle)
    }

    private var currentUserMemberIds: Set<UUID> {
        Set(circles.flatMap(\.members).filter(\.isCurrentUser).map(\.id))
    }

    private var playerSessionResults: [PlayerSessionStats.Result] {
        PlayerSessionStats.results(
            circles: circles,
            memberIds: currentUserMemberIds,
            displayName: displayName,
            preferredCurrencyCode: preferredCurrencyCode
        )
    }

    private var totalWon: Decimal {
        PlayerSessionStats.convertedNetTotal(in: playerSessionResults)
    }

    private var bestNight: Decimal {
        PlayerSessionStats.bestNightAmount(in: playerSessionResults)
    }

    private var worstNight: Decimal {
        PlayerSessionStats.worstNightAmount(in: playerSessionResults)
    }

    private var bestNightHighlight: PlayerSessionHighlight? {
        PlayerSessionStats.bestNight(in: playerSessionResults)
    }

    private var worstNightHighlight: PlayerSessionHighlight? {
        PlayerSessionStats.worstNight(in: playerSessionResults)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    profileHeader

                    statGrid

                    Button {
                        settingsInitialTab = .currency
                        showProfileControls = true
                    } label: {
                        HStack(spacing: 12) {
                            Text(MoneyFormatting.currencySymbol(for: preferredCurrencyCode))
                                .font(.headline.weight(.bold))
                                .frame(width: 36, height: 36)
                                .background(AppTheme.background)
                                .foregroundStyle(AppTheme.text)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Currency")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.text)
                                Text(preferredCurrencyLabel)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.muted)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.muted)
                        }
                        .padding()
                        .background(AppTheme.card)
                        .foregroundStyle(AppTheme.text)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                .stroke(AppTheme.cardBorder)
                        )
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(rateStatusText)
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)

                        Button {
                            showAddFriend = true
                        } label: {
                            Label("Add friend", systemImage: "person.badge.plus")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppTheme.card)
                                .foregroundStyle(AppTheme.text)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                        .stroke(AppTheme.cardBorder)
                                )
                        }
                        .buttonStyle(.plain)

                        if !outgoingFriendRequests.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("FRIEND REQUESTS")
                                    .font(.caption2.weight(.bold))
                                    .tracking(AppTheme.sectionTracking)
                                    .foregroundStyle(AppTheme.muted)

                                ForEach(outgoingFriendRequests) { request in
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(request.targetDisplayName ?? request.targetHandle)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(AppTheme.text)
                                            Text(request.targetHandle)
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.muted)
                                        }
                                        Spacer()
                                        Text(friendRequestStatusLabel(request.status))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(AppTheme.positive)
                                    }
                                    .padding(12)
                                    .background(AppTheme.card)
                                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(AppTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                rateStatusText = ExchangeRateService.shared.rateStatusText
                Task {
                    await authManager.refreshSession()
                    await ExchangeRateService.shared.refreshIfNeeded()
                    rateStatusText = ExchangeRateService.shared.rateStatusText
                    await syncUserProfileIfNeeded()
                    if authManager.isSignedIn {
                        await CloudSyncCoordinator.syncAll(
                            context: context,
                            displayName: displayName,
                            playerHandle: playerHandle
                        )
                    }
                }
            }
            .sheet(isPresented: $showProfileControls) {
                ProfileControlsView(
                    isPresented: $showProfileControls,
                    displayName: $displayName,
                    playerHandle: $playerHandle,
                    countryCode: $countryCode,
                    preferredCurrencyCode: $preferredCurrencyCode,
                    initialTab: settingsInitialTab
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .onChange(of: showProfileControls) { _, isShowing in
                if !isShowing {
                    settingsInitialTab = .profile
                }
            }
            .sheet(isPresented: $showAddFriend) {
                AddFriendSheet()
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSignIn) {
                SignInSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var outgoingFriendRequests: [FriendRequestModel] {
        friendRequests.filter { $0.status == .pending || $0.status == .sent }
    }

    private func friendRequestStatusLabel(_ status: FriendRequestStatus) -> String {
        switch status {
        case .pending:
            return "Pending"
        case .sent:
            return "Sent"
        case .accepted:
            return "Accepted"
        case .declined:
            return "Declined"
        }
    }

    private func syncUserProfileIfNeeded() async {
        guard
            SupabaseBootstrap.isConfigured,
            authManager.isSignedIn,
            let handle = profileHandle,
            !MemberModel.isPlaceholderHandle(handle)
        else {
            return
        }

        try? await SupabaseSyncService.shared.upsertUserProfile(
            handle: handle,
            displayName: profileDisplayName
        )
    }

    private var profileHeader: some View {
        VStack(spacing: 14) {
            HStack {
                Spacer()
                Button {
                    settingsInitialTab = .profile
                    showProfileControls = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.text)
                        .frame(width: 42, height: 42)
                        .background(AppTheme.card)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppTheme.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Text("PLAYER PROFILE")
                .font(.caption2.weight(.bold))
                .tracking(AppTheme.sectionTracking)
                .foregroundStyle(AppTheme.gold.opacity(0.75))

            Text(String(profileDisplayName.prefix(1)).uppercased())
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.contrastText)
                .frame(width: 92, height: 92)
                .background(Circle().fill(AppTheme.gold))
                .overlay(Circle().stroke(AppTheme.contrastText.opacity(0.4), lineWidth: 4))
                .overlay(Circle().stroke(AppTheme.gold.opacity(0.8), lineWidth: 1).padding(-5))

            VStack(spacing: 8) {
                Text(profileDisplayName)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(AppTheme.text)

                HStack(spacing: 10) {
                    if let handle = profileHandle {
                        Text(handle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.gold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppTheme.gold.opacity(0.14))
                            .clipShape(Capsule())
                    }

                    Text(profileSubtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
            }
        }
    }

    private var preferredCurrencyLabel: String {
        if let option = CurrencyPreferences.options.first(where: { $0.currencyCode == preferredCurrencyCode }) {
            return "\(option.currencyCode) · \(option.currencyName)"
        }
        return preferredCurrencyCode
    }

    private var profileSubtitle: String {
        let circleNames = circles
            .filter { circle in circle.members.contains(where: \.isCurrentUser) }
            .map(\.name)

        return circleNames.first ?? "No circle yet"
    }

    private var statGrid: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                statBox(
                    title: "TOTAL",
                    value: MoneyFormatting.format(totalWon, currencyCode: preferredCurrencyCode),
                    tint: totalWon < 0 ? AppTheme.negative : AppTheme.positive
                )
                NavigationLink {
                    ProfileGamesDetailView(
                        displayName: currentMember?.displayName ?? displayName,
                        preferredCurrencyCode: preferredCurrencyCode
                    )
                } label: {
                    statBox(
                        title: "GAMES",
                        value: "\(playerSessionResults.count)",
                        tint: AppTheme.text
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 14) {
                statBoxLink(
                    title: "BEST NIGHT",
                    value: MoneyFormatting.format(bestNight, currencyCode: preferredCurrencyCode),
                    tint: AppTheme.positive,
                    highlight: bestNightHighlight
                )
                statBoxLink(
                    title: "WORST NIGHT",
                    value: MoneyFormatting.format(worstNight, currencyCode: preferredCurrencyCode),
                    tint: worstNight < 0 ? AppTheme.negative : AppTheme.text,
                    highlight: worstNightHighlight
                )
            }
        }
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
                .font(.title.weight(.heavy))
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding()
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }
}

private struct ProfileControlsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @AppStorage("appAppearance") private var appAppearance = AppAppearancePreference.dark.rawValue
    @Query private var circles: [CircleModel]

    @Binding var isPresented: Bool
    @Binding var displayName: String
    @Binding var playerHandle: String
    @Binding var countryCode: String
    @Binding var preferredCurrencyCode: String

    let initialTab: SettingsTab

    @State private var draftDisplayName: String
    @State private var draftCountryCode: String
    @State private var draftCurrencyCode: String
    @State private var currencySearchText = ""
    @State private var draftAppearance: AppAppearancePreference
    @State private var errorMessage: String?
    @State private var authManager = SupabaseAuthManager.shared
    @State private var showSignIn = false
    @State private var suggestedNickname = "@yourname"
    @State private var isSaving = false
    @State private var selectedTab: SettingsTab = .profile
    @State private var showDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var accountActionError: String?

    private var hasChanges: Bool {
        draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines) != displayName ||
        suggestedNickname != playerHandle ||
        draftCountryCode != countryCode ||
        CurrencyPreferences.normalizedCurrencyCode(draftCurrencyCode) != CurrencyPreferences.normalizedCurrencyCode(preferredCurrencyCode) ||
        draftAppearance.rawValue != appAppearance
    }

    private var currentUserMemberIds: Set<UUID> {
        Set(circles.flatMap(\.members).filter(\.isCurrentUser).map(\.id))
    }

    private var filteredCurrencyOptions: [CurrencyPreference] {
        let query = currencySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return CurrencyPreferences.options }

        return CurrencyPreferences.options.filter { option in
            option.currencyCode.localizedCaseInsensitiveContains(query) ||
            option.currencyName.localizedCaseInsensitiveContains(query) ||
            option.countryName.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedCurrencyLabel: String {
        if let option = CurrencyPreferences.options.first(where: { $0.currencyCode == draftCurrencyCode }) {
            return "\(option.currencyCode) · \(option.currencyName)"
        }
        return draftCurrencyCode
    }

    init(
        isPresented: Binding<Bool>,
        displayName: Binding<String>,
        playerHandle: Binding<String>,
        countryCode: Binding<String>,
        preferredCurrencyCode: Binding<String>,
        initialTab: SettingsTab = .profile
    ) {
        self._isPresented = isPresented
        self._displayName = displayName
        self._playerHandle = playerHandle
        self._countryCode = countryCode
        self._preferredCurrencyCode = preferredCurrencyCode
        self.initialTab = initialTab
        self._draftDisplayName = State(initialValue: displayName.wrappedValue)
        self._draftCountryCode = State(initialValue: countryCode.wrappedValue)
        self._draftCurrencyCode = State(initialValue: preferredCurrencyCode.wrappedValue)
        self._draftAppearance = State(initialValue: AppAppearancePreference(rawValue: UserDefaults.standard.string(forKey: "appAppearance") ?? "") ?? .dark)
        self._suggestedNickname = State(initialValue: playerHandle.wrappedValue)
        self._selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Settings section", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedTab {
                        case .profile:
                            profileTab
                        case .currency:
                            currencyTab
                        case .appearance:
                            appearanceTab
                        }

                        accountSection

                        if let accountActionError {
                            Text(accountActionError)
                                .font(.caption)
                                .foregroundStyle(AppTheme.negative)
                        }
                    }
                    .padding()
                }
            }
            .background(AppTheme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.muted)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveChanges() }
                    }
                    .disabled(!hasChanges || isSaving || errorMessage != nil)
                    .foregroundStyle(hasChanges ? AppTheme.positive : AppTheme.muted)
                }
            }
            .task(id: draftDisplayName) {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                refreshSuggestedNickname()
                validateDisplayName()
            }
            .sheet(isPresented: $showSignIn) {
                SignInSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                selectedTab = initialTab
            }
            .alert("Delete account?", isPresented: $showDeleteAccountConfirmation) {
                Button("Delete account", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your Pot Master account, cloud profile, owned circles, and synced data on this device.")
            }
        }
    }

    private var profileTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Real name", text: $draftDisplayName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(AppTheme.card)
                    .foregroundStyle(AppTheme.text)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.negative)
                }

                Text(suggestedNickname)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(AppTheme.card)
                    .foregroundStyle(AppTheme.text)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }

            Text("Real names and nicknames must be unique across all Pot Master players.")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)

            Button {
                selectedTab = .currency
            } label: {
                HStack {
                    Text("Currency")
                        .foregroundStyle(AppTheme.text)
                    Spacer()
                    Text(selectedCurrencyLabel)
                        .foregroundStyle(AppTheme.muted)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.muted)
                }
                .font(.subheadline)
                .padding()
            }
            .buttonStyle(.plain)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

            VStack(spacing: 0) {
                aboutRow(title: "App", value: "Pot Master")
                Divider().overlay(AppTheme.cardBorder)
                aboutRow(title: "Version", value: "1.0")
                Divider().overlay(AppTheme.cardBorder)
                aboutRow(title: "Cloud sync", value: cloudSyncStatusLabel)
            }
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

            if !cloudSyncDescription.isEmpty {
                Text(cloudSyncDescription)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
        }
    }

    private var accountSection: some View {
        VStack(spacing: 0) {
            aboutRow(
                title: "Account",
                value: authManager.isSignedIn ? (authManager.email ?? "Signed in") : "Not signed in"
            )

            if authManager.isSignedIn {
                Divider().overlay(AppTheme.cardBorder)
                Button {
                    Task {
                        await AccountSessionCoordinator.signOut(context: context, router: router)
                    }
                } label: {
                    HStack {
                        Text("Sign out")
                            .foregroundStyle(AppTheme.negative)
                        Spacer()
                    }
                    .font(.subheadline)
                    .padding()
                }
                .buttonStyle(.plain)

                Divider().overlay(AppTheme.cardBorder)
                Button {
                    showDeleteAccountConfirmation = true
                } label: {
                    HStack {
                        Text("Delete account")
                            .foregroundStyle(AppTheme.negative)
                        Spacer()
                    }
                    .font(.subheadline)
                    .padding()
                }
                .buttonStyle(.plain)
                .disabled(isDeletingAccount)
            } else if SupabaseBootstrap.isConfigured {
                Divider().overlay(AppTheme.cardBorder)
                Button {
                    showSignIn = true
                } label: {
                    HStack {
                        Text("Sign in")
                            .foregroundStyle(AppTheme.positive)
                        Spacer()
                    }
                    .font(.subheadline)
                    .padding()
                }
                .buttonStyle(.plain)
            }
        }
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    private func deleteAccount() async {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        accountActionError = nil
        defer { isDeletingAccount = false }

        do {
            try await AccountSessionCoordinator.deleteAccount(context: context, router: router)
            isPresented = false
            dismiss()
        } catch {
            accountActionError = error.localizedDescription
        }
    }

    private var currencyTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose the currency for your profile stats. Circle currencies are changed inside each circle.")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)

            TextField("Currency code (e.g. USD, ILS, JPY)", text: $draftCurrencyCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding()
                .background(AppTheme.card)
                .foregroundStyle(AppTheme.text)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .onChange(of: draftCurrencyCode) { _, newValue in
                    draftCurrencyCode = CurrencyPreferences.normalizedCurrencyCode(newValue)
                }

            TextField("Search every world currency", text: $currencySearchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(AppTheme.card)
                .foregroundStyle(AppTheme.text)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

            PaginatedCurrencyList(
                options: filteredCurrencyOptions,
                selectedCurrencyCode: draftCurrencyCode
            ) { option, isLast in
                Button {
                    draftCountryCode = option.countryCode
                    draftCurrencyCode = option.currencyCode
                } label: {
                    HStack(spacing: 12) {
                        Text(MoneyFormatting.currencySymbol(for: option.currencyCode))
                            .font(.headline.weight(.bold))
                            .frame(width: 30, height: 30)
                            .background(draftCurrencyCode == option.currencyCode ? AppTheme.positive : AppTheme.background)
                            .foregroundStyle(draftCurrencyCode == option.currencyCode ? AppTheme.contrastText : AppTheme.muted)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(MoneyFormatting.currencySymbol(for: option.currencyCode)) \(option.currencyName)")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(AppTheme.text)
                            Text("\(option.currencyCode) · \(option.countryName)")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.muted)
                        }

                        Spacer()

                        if draftCurrencyCode == option.currencyCode {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AppTheme.positive)
                        }
                    }
                    .padding()
                }
                .buttonStyle(.plain)

                if !isLast {
                    Divider().overlay(AppTheme.cardBorder)
                }
            }
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
    }

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose how Pot Master looks on this device.")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)

            HStack(spacing: 10) {
                ForEach(AppAppearancePreference.allCases) { option in
                    Button {
                        draftAppearance = option
                    } label: {
                        Label(option.title, systemImage: option.iconName)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(draftAppearance == option ? AppTheme.positive : AppTheme.background)
                            .foregroundStyle(draftAppearance == option ? AppTheme.contrastText : AppTheme.text)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
    }

    private var cloudSyncStatusLabel: String {
        if !SupabaseBootstrap.isConfigured { return "Needs setup" }
        if authManager.isSignedIn { return "Signed in" }
        return "Sign in required"
    }

    private var cloudSyncDescription: String {
        if !SupabaseBootstrap.isConfigured {
            return SupabaseBootstrap.missingConfigurationMessage
        }
        if authManager.isSignedIn {
            return ""
        }
        return "Sign in with Apple, Google, or email to sync circles and friend requests across devices."
    }

    private func aboutRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(AppTheme.text)
            Spacer()
            Text(value)
                .foregroundStyle(AppTheme.muted)
        }
        .font(.subheadline)
        .padding()
    }

    private func validateDisplayName() {
        let cleanedDisplayName = draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedDisplayName.isEmpty, !MemberModel.isPlaceholderName(cleanedDisplayName) else {
            errorMessage = nil
            return
        }

        if DisplayNameService.localReservedDisplayNames(in: context).contains(cleanedDisplayName.lowercased()) {
            errorMessage = SupabaseSyncError.displayNameTaken(cleanedDisplayName).errorDescription
            return
        }

        errorMessage = nil
    }

    private func refreshSuggestedNickname() {
        let cleanedDisplayName = draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedDisplayName.isEmpty else {
            suggestedNickname = playerHandle
            return
        }

        suggestedNickname = NicknameService.generateAvailableLocally(
            for: cleanedDisplayName,
            in: context
        )
    }

    private func saveChanges() async {
        let cleanedDisplayName = draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedDisplayName.isEmpty else {
            errorMessage = "Add your name before saving."
            return
        }

        let cleanedCurrencyCode = CurrencyPreferences.normalizedCurrencyCode(draftCurrencyCode)
        guard CurrencyPreferences.isValidCurrencyCode(cleanedCurrencyCode) else {
            errorMessage = "Use a valid 3-letter ISO currency code, like USD or JPY."
            return
        }

        guard errorMessage == nil else { return }

        isSaving = true
        defer { isSaving = false }

        let nameChanged = cleanedDisplayName != displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedHandle = nameChanged ? suggestedNickname : playerHandle

        displayName = cleanedDisplayName
        playerHandle = cleanedHandle
        countryCode = CurrencyPreferences.options.first { $0.currencyCode == cleanedCurrencyCode }?.countryCode ?? draftCountryCode
        appAppearance = draftAppearance.rawValue

        persistLocalProfileChanges(displayName: cleanedDisplayName, handle: cleanedHandle)

        if CurrencyPreferences.normalizedCurrencyCode(preferredCurrencyCode) != cleanedCurrencyCode {
            preferredCurrencyCode = cleanedCurrencyCode
        }

        isPresented = false
        dismiss()

        if nameChanged {
            Task {
                try? await DisplayNameService.validateAvailable(cleanedDisplayName, in: context)
                try? await NicknameService.validateAvailable(cleanedHandle, in: context)
                if let handle = MemberModel.normalizedHandle(cleanedHandle) {
                    try? await SupabaseSyncService.shared.upsertUserProfile(
                        handle: handle,
                        displayName: cleanedDisplayName
                    )
                }
            }
        }
    }

    private func persistLocalProfileChanges(displayName: String, handle: String?) {
        for member in circles.flatMap(\.members).filter(\.isCurrentUser) {
            member.displayName = displayName
            member.initial = CircleRepository.initial(for: displayName)
            member.handle = handle
            if let circle = member.circle {
                for session in circle.sessions {
                    for player in session.players where player.memberId == member.id {
                        player.displayName = member.displayName(preferredHandle: handle)
                        player.initial = member.initial
                    }
                }

                Task {
                    try? await SupabaseSyncService.shared.upsertMember(member, in: circle)
                }
            }
        }
        try? context.save()
    }
}

private struct ProfileGamesDetailView: View {
    let displayName: String
    let preferredCurrencyCode: String

    @Query private var circles: [CircleModel]

    private var currentUserMemberIds: Set<UUID> {
        Set(circles.flatMap(\.members).filter(\.isCurrentUser).map(\.id))
    }

    private var playerSessionResults: [PlayerSessionStats.Result] {
        PlayerSessionStats.results(
            circles: circles,
            memberIds: currentUserMemberIds,
            displayName: displayName,
            preferredCurrencyCode: preferredCurrencyCode
        )
    }

    private var sessionsWon: Int {
        playerSessionResults.filter { $0.convertedNet > 0 }.count
    }

    private var sessionsLost: Int {
        playerSessionResults.filter { $0.convertedNet <= 0 }.count
    }

    private var biggestWin: Decimal {
        PlayerSessionStats.bestNightAmount(in: playerSessionResults)
    }

    private var lastGame: Decimal {
        playerSessionResults.first?.convertedNet ?? 0
    }

    private var biggestWinHighlight: PlayerSessionHighlight? {
        PlayerSessionStats.bestNight(in: playerSessionResults)
    }

    private var lastGameHighlight: PlayerSessionHighlight? {
        PlayerSessionStats.lastGame(in: playerSessionResults)
    }

    private var opponentName: String {
        var counts: [String: Int] = [:]
        let memberIds = currentUserMemberIds

        for item in playerSessionResults {
            for player in item.session.players {
                if let memberId = player.memberId, memberIds.contains(memberId) {
                    continue
                }
                if player.displayName == displayName {
                    continue
                }
                counts[player.displayName, default: 0] += 1
            }
        }

        return counts.max { $0.value < $1.value }?.key ?? "Losses"
    }

    private var winShare: CGFloat {
        let total = sessionsWon + sessionsLost
        guard total > 0 else { return 0.5 }
        return CGFloat(sessionsWon) / CGFloat(total)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                sessionsWonCard

                HStack(spacing: 20) {
                    detailStatCardLink(
                        title: "BIGGEST WIN",
                        value: MoneyFormatting.format(biggestWin, currencyCode: preferredCurrencyCode),
                        highlight: biggestWinHighlight
                    )
                    detailStatCardLink(
                        title: "LAST GAME",
                        value: MoneyFormatting.format(lastGame, currencyCode: preferredCurrencyCode),
                        highlight: lastGameHighlight
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
        .background(AppTheme.background)
        .navigationTitle("Games")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sessionsWonCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Sessions won")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.text)

                Spacer()

                Text("\(sessionsWon) - \(sessionsLost)")
                    .font(.title3.weight(.bold))
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
                Text("\(displayName) \(sessionsWon)")
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

    private func detailStatCardLink(
        title: String,
        value: String,
        highlight: PlayerSessionHighlight?
    ) -> some View {
        Group {
            if let highlight {
                NavigationLink {
                    HistorySessionDetailView(session: highlight.session, circle: highlight.circle)
                } label: {
                    detailStatCard(title: title, value: value)
                }
                .buttonStyle(.plain)
            } else {
                detailStatCard(title: title, value: value)
            }
        }
    }

    private func detailStatCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.caption.weight(.heavy))
                .tracking(2)
                .foregroundStyle(AppTheme.muted)

            Text(value)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .foregroundStyle(value.hasPrefix("-") ? AppTheme.negative : AppTheme.positive)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(24)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }
}

private struct EditProfileView: View {
    @Binding var displayName: String

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Real name", text: $displayName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle("Profile")
    }
}

private struct AppSettingsView: View {
    @Binding var countryCode: String
    @Binding var preferredCurrencyCode: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Currency")
                        .font(.headline)
                        .foregroundStyle(AppTheme.text)
                    Text("Choose the currency for your profile stats. Circle currencies are changed inside each circle.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }

                VStack(spacing: 0) {
                    ForEach(CurrencyPreferences.options) { option in
                        Button {
                            apply(option)
                        } label: {
                            HStack(spacing: 12) {
                                Text(MoneyFormatting.currencySymbol(for: option.currencyCode))
                                    .font(.headline.weight(.bold))
                                    .frame(width: 30, height: 30)
                                    .background(preferredCurrencyCode == option.currencyCode ? AppTheme.positive : AppTheme.background)
                                    .foregroundStyle(preferredCurrencyCode == option.currencyCode ? AppTheme.contrastText : AppTheme.muted)
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(MoneyFormatting.currencySymbol(for: option.currencyCode)) \(option.currencyName)")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(AppTheme.text)
                                    Text("\(option.currencyCode) · \(option.countryName)")
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.muted)
                                }
                                Spacer()
                                if preferredCurrencyCode == option.currencyCode {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppTheme.positive)
                                }
                            }
                            .padding()
                        }
                        .buttonStyle(.plain)

                        if option != CurrencyPreferences.options.last {
                            Divider().overlay(AppTheme.cardBorder)
                        }
                    }
                }
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func apply(_ option: CurrencyPreference) {
        countryCode = option.countryCode
        preferredCurrencyCode = option.currencyCode
    }
}

