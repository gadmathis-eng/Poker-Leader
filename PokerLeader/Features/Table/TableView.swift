import SwiftUI
import SwiftData

struct TableView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @AppStorage("personalSessionCurrencyCode") private var personalSessionCurrencyCode = CurrencyPreferences.defaultCurrencyCode
    @AppStorage("personalBuyInCurrencyCode") private var personalBuyInCurrencyCode = CurrencyPreferences.defaultCurrencyCode
    @AppStorage("personalBuyInAmount") private var personalBuyInAmountString = ""
    @AppStorage("displayName") private var displayName = "Your name"

    @State private var draftSessionCurrencyCode = CurrencyPreferences.defaultCurrencyCode
    @State private var draftBuyInCurrencyCode = CurrencyPreferences.defaultCurrencyCode
    @State private var draftBuyInText = "0"
    @State private var showingSeatSelection = false
    @Query(sort: \OpenTableModel.updatedAt, order: .reverse) private var tables: [OpenTableModel]
    @State private var showEditTables = false
    @State private var activeTable: OpenTableModel?
    @State private var joinError: String?
    @State private var joinCodeText = ""
    @State private var isJoiningTable = false
    @State private var showCreateTable = false
    @State private var showJoinBuyIn = false
    @State private var didConfirmJoinBuyIn = false
    @State private var showSignIn = false
    @State private var authManager = SupabaseAuthManager.shared
    @State private var tableListEpoch = 0

    /// Every table but the one that is open, so the card at the top is not
    /// repeated in the list underneath it.
    private var otherTables: [OpenTableModel] {
        _ = tableListEpoch
        return TableOrderStore.ordered(tables).filter { $0.inviteCode != activeTable?.inviteCode }
    }

    private var repo: TableRepository { TableRepository(context: context) }

    private var personalBuyInAmount: Decimal? {
        guard !personalBuyInAmountString.isEmpty else { return nil }
        return Decimal(string: personalBuyInAmountString)?.clampedToNonNegative
    }

    private var draftBuyInAmount: Decimal? {
        Decimal(string: draftBuyInText.trimmingCharacters(in: .whitespacesAndNewlines))?.clampedToNonNegative
    }

    private var canSaveBuyIn: Bool {
        (draftBuyInAmount ?? 0) > 0
    }

    private var tableSessionCurrencyCode: String {
        activeTable?.sessionCurrencyCode ?? personalSessionCurrencyCode
    }

    private var hasJoinableBuyIn: Bool {
        (personalBuyInAmount ?? 0) > 0
    }

    private var canJoinWithTypedCode: Bool {
        !TableInviteDeepLink.pastedInviteCode(joinCodeText).isEmpty
    }

    private var buyInButtonTitle: String {
        guard let activeTable else { return "Save and open" }
        return activeTable.isHostLocally ? "Save and open" : "Join table"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    banner

                    CreateTableButton {
                        showCreateTable = true
                    }
                    .padding(.horizontal)

                    if let activeTable {
                        activeTableCard(activeTable)
                    }

                    buyInSection

                    joinSection

                    otherTablesSection
                }
                .padding(.vertical)
            }
            .background(AppTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEditTables = true } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.body.weight(.medium))
                            .accessibilityLabel("Edit tables")
                    }
                }
            }
            .onAppear(perform: loadDraftValues)
            .task {
                loadActiveTable()
                if router.pendingTableInviteCode == nil {
                    await republishHostTableIfNeeded()
                }
                await handlePendingJoin()
            }
            .onChange(of: router.pendingTableInviteCode) { _, _ in
                Task { await handlePendingJoin() }
            }
            .navigationDestination(isPresented: $showingSeatSelection) {
                TableSeatSelectionView(
                    buyInAmount: personalBuyInAmount ?? 0,
                    buyInCurrencyCode: personalBuyInCurrencyCode,
                    sessionCurrencyCode: tableSessionCurrencyCode
                )
            }
            .sheet(isPresented: $showEditTables, onDismiss: handleTablesChanged) {
                EditTablesSheet(
                    tables: TableOrderStore.ordered(tables),
                    onTablesChanged: handleTablesChanged
                )
            }
            .sheet(isPresented: $showCreateTable, onDismiss: handleTablesChanged) {
                CreateTableSheet()
            }
            .sheet(isPresented: $showJoinBuyIn) {
                JoinBuyInSheet(
                    hostName: activeTable?.hostDisplayName ?? "",
                    tableCurrencyCode: tableSessionCurrencyCode,
                    initialPayInCurrencyCode: personalBuyInCurrencyCode,
                    initialAmount: 0,
                    onConfirm: confirmJoinBuyIn
                )
                .presentationDetents([.height(580)])
                .presentationDragIndicator(.hidden)
            }
            .onChange(of: activeTable?.inviteCode) { _, _ in
                didConfirmJoinBuyIn = false
            }
            .sheet(isPresented: $showSignIn) {
                SignInSheet()
                    .modelContext(context)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: showSignIn) { _, isPresented in
                if !isPresented {
                    Task { await handlePendingJoin() }
                }
            }
            .onChange(of: authManager.isSignedIn) { _, signedIn in
                if signedIn {
                    showSignIn = false
                    Task {
                        await republishHostTableIfNeeded()
                        await handlePendingJoin()
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Table")
                .font(.largeTitle.bold())
                .foregroundStyle(AppTheme.text)
            Text("Create a table with a currency, buy-in, and ante, then share the code. Everyone who joins chooses how much they sit down with.")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .padding(.horizontal)
    }

    /// One message at a time, whichever matters most right now.
    @ViewBuilder
    private var banner: some View {
        if SupabaseBootstrap.isConfigured, !authManager.isSignedIn {
            signInBanner
        } else if let joinError {
            noticeCard(
                title: "That did not work",
                message: joinError,
                tint: AppTheme.negative
            )
        } else if let activeTable, !activeTable.isHostLocally {
            noticeCard(
                title: "You're joining \(activeTable.hostDisplayName)'s table",
                message: "Choose how much you want to put in, then pick an open seat.",
                tint: AppTheme.text
            )
        }
    }

    private func noticeCard(title: String, message: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(tint)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 16)
        .padding(.horizontal)
    }

    private var signInBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(router.pendingTableInviteCode == nil ? "Sign in to share a table" : "Sign in to join this table")
                .font(.headline)
                .foregroundStyle(AppTheme.text)
            Text(
                router.pendingTableInviteCode == nil
                    ? "A table on this phone stays private until you sign in. Then friends can join with the 6-character code."
                    : "The host shared a link. Sign in and you'll sit at their table."
            )
            .font(.caption)
            .foregroundStyle(AppTheme.muted)
            Button("Sign in") {
                showSignIn = true
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(AppTheme.contrastText)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppTheme.positive)
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 16)
        .padding(.horizontal)
    }

    /// The table you are at, with the one thing you came here to do on it.
    private func activeTableCard(_ table: OpenTableModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(table.displayTitle)
                        .font(.headline)
                        .foregroundStyle(AppTheme.text)
                        .lineLimit(1)
                    Text(activeTableSummary(table))
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer(minLength: 0)
                InviteCodeCopyLabel(code: table.inviteCode, fill: AppTheme.background)
            }

            Button {
                presentJoinOrOpen()
            } label: {
                Text(joinOrOpenTitle(for: table))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.positive)
                    .foregroundStyle(AppTheme.contrastText)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                if authManager.isSignedIn {
                    ShareLink(
                        item: TableInviteSharing.url(forInviteCode: table.inviteCode),
                        subject: Text("Join my Pot Master table"),
                        message: Text(
                            TableInviteSharing.message(
                                forInviteCode: table.inviteCode,
                                hostName: table.hostDisplayName
                            )
                        )
                    ) {
                        secondaryLabel("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink {
                    EditTableView(table: table, onChange: handleTablesChanged)
                } label: {
                    secondaryLabel("Edit", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
            }

            if table.isHostLocally, !hasJoinableBuyIn {
                Text("Set a buy-in below to sit down.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .cardSurface(padding: 16)
        .padding(.horizontal)
    }

    private func secondaryLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(AppTheme.background)
            .foregroundStyle(AppTheme.text)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.cardBorder)
            )
    }

    private func activeTableSummary(_ table: OpenTableModel) -> String {
        let seated = table.seats.count
        let seatedText = seated == 1 ? "1 seated" : "\(seated) seated"
        let role = table.isHostLocally ? "You host" : "You joined"
        return "\(role) · \(seatedText) · \(table.sessionCurrencyCode)"
    }

    private func joinOrOpenTitle(for table: OpenTableModel) -> String {
        shouldAskJoinBuyIn(for: table) ? "Join table" : "Open table"
    }

    /// Guests who have not sat yet must say how much they are putting in
    /// before they get onto the felt.
    private func shouldAskJoinBuyIn(for table: OpenTableModel) -> Bool {
        guard !table.isHostLocally else { return false }
        if didConfirmJoinBuyIn { return false }
        return repo.mySeat(on: table) == nil
    }

    private func presentJoinOrOpen() {
        guard let table = activeTable else { return }
        if shouldAskJoinBuyIn(for: table) {
            showJoinBuyIn = true
            return
        }
        showingSeatSelection = true
    }

    /// Wait for a join sheet or tab switch to finish so this ask is not buried.
    private func presentJoinBuyInAfterJoin() async {
        try? await Task.sleep(for: .milliseconds(400))
        showJoinBuyIn = true
    }

    private func confirmJoinBuyIn(_ amount: Decimal, currencyCode: String) {
        let payIn = CurrencyPreferences.isValidCurrencyCode(currencyCode)
            ? CurrencyPreferences.normalizedCurrencyCode(currencyCode)
            : tableSessionCurrencyCode
        personalBuyInCurrencyCode = payIn
        personalBuyInAmountString = NSDecimalNumber(decimal: amount).stringValue
        draftBuyInCurrencyCode = payIn
        draftBuyInText = personalBuyInAmountString
        didConfirmJoinBuyIn = true
        showingSeatSelection = true
    }

    private var buyInSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your buy-in")

            DualCurrencyBuyInSetup(
                sessionCurrencyCode: $draftSessionCurrencyCode,
                buyInCurrencyCode: $draftBuyInCurrencyCode,
                buyInText: $draftBuyInText
            )

            Text("This is how much you sit down with. Other players choose their own.")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)

            Button {
                Task { await savePersonalBuyIn() }
            } label: {
                Text(buyInButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canSaveBuyIn ? AppTheme.positive : AppTheme.card)
                    .foregroundStyle(canSaveBuyIn ? AppTheme.contrastText : AppTheme.muted)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
            .buttonStyle(.plain)
            .disabled(!canSaveBuyIn)
        }
        .padding(.horizontal)
    }

    private var joinSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Join a friend's table")

            HStack(spacing: 10) {
                TextField("Table code", text: $joinCodeText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.headline.monospaced())
                    .frame(maxWidth: .infinity)

                Button {
                    Task { await joinWithTypedCode() }
                } label: {
                    Text(isJoiningTable ? "Joining..." : "Join")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(canJoinWithTypedCode ? AppTheme.positive : AppTheme.background)
                        .foregroundStyle(canJoinWithTypedCode ? AppTheme.contrastText : AppTheme.muted)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canJoinWithTypedCode || isJoiningTable)
            }
            .cardSurface()
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var otherTablesSection: some View {
        if !otherTables.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: "Your other tables")
                    Spacer()
                    Button("Edit") { showEditTables = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.positive)
                }

                ForEach(otherTables) { table in
                    tableSummaryLink(table)
                }
            }
            .padding(.horizontal)
        }
    }

    private func tableSummaryLink(_ table: OpenTableModel) -> some View {
        NavigationLink {
            EditTableView(table: table, onChange: handleTablesChanged)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(table.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.text)
                        .lineLimit(1)
                    Text(tableListSummary(for: table))
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
            }
            .cardSurface()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open table") {
                repo.makeActive(table)
                handleTablesChanged()
            }
            if table.isHostLocally {
                ShareLink(
                    item: TableInviteSharing.url(forInviteCode: table.inviteCode),
                    subject: Text("Join my Pot Master table"),
                    message: Text(
                        TableInviteSharing.message(
                            forInviteCode: table.inviteCode,
                            hostName: table.hostDisplayName
                        )
                    )
                ) {
                    Label("Share table", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func tableListSummary(for table: OpenTableModel) -> String {
        let seated = table.seats.count
        let seatedText = seated == 1 ? "1 seated" : "\(seated) seated"
        let role = table.isHostLocally ? "Host" : "Joined"
        return "\(role) · \(table.inviteCode) · \(seatedText) · \(table.sessionCurrencyCode)"
    }

    private func loadDraftValues() {
        draftSessionCurrencyCode = tableSessionCurrencyCode
        draftBuyInCurrencyCode = personalBuyInCurrencyCode
        draftBuyInText = personalBuyInAmountString.isEmpty
            ? "0"
            : personalBuyInAmountString
    }

    private func loadActiveTable() {
        activeTable = try? repo.activeTable()
        if let table = activeTable, !table.isHostLocally {
            draftSessionCurrencyCode = table.sessionCurrencyCode
        }
    }

    private func handleTablesChanged() {
        activeTable = try? repo.activeTable()
        draftSessionCurrencyCode = tableSessionCurrencyCode
        tableListEpoch += 1
    }

    private func savePersonalBuyIn() async {
        guard let amount = draftBuyInAmount else { return }
        personalBuyInCurrencyCode = draftBuyInCurrencyCode
        personalBuyInAmountString = NSDecimalNumber(decimal: amount).stringValue

        if activeTable?.isHostLocally != false {
            personalSessionCurrencyCode = draftSessionCurrencyCode
        }

        if activeTable == nil {
            showCreateTable = true
            return
        } else if let table = activeTable, table.isHostLocally {
            table.sessionCurrencyCode = draftSessionCurrencyCode
            table.hostDisplayName = displayName
        }

        if let table = activeTable, table.isHostLocally {
            await publishHostTable(table)
            if joinError != nil {
                return
            }
        }

        if activeTable?.isHostLocally == false {
            didConfirmJoinBuyIn = true
        }
        showingSeatSelection = true
    }

    /// A table created before the host signed in never reached the cloud, so it
    /// is uploaded again as soon as an account is available.
    private func republishHostTableIfNeeded() async {
        guard let table = activeTable, table.isHostLocally else { return }
        guard SupabaseBootstrap.isConfigured, authManager.isSignedIn else { return }
        await publishHostTable(table)
    }

    private func joinWithTypedCode() async {
        let code = TableInviteDeepLink.pastedInviteCode(joinCodeText)
        guard !code.isEmpty else { return }

        router.pendingTableInviteCode = code
        await handlePendingJoin()
    }

    private func publishHostTable(_ table: OpenTableModel) async {
        do {
            try await repo.publishForSharing(table)
            joinError = nil
        } catch {
            joinError = error.localizedDescription
        }
    }

    private func handlePendingJoin() async {
        guard let code = router.pendingTableInviteCode else { return }
        guard !isJoiningTable else { return }

        if SupabaseBootstrap.isConfigured, !SupabaseAuthManager.shared.isSignedIn {
            return
        }

        isJoiningTable = true
        joinError = nil
        defer { isJoiningTable = false }

        do {
            let table = try await repo.join(inviteCode: code, displayName: displayName)
            if activeTable?.inviteCode != table.inviteCode {
                didConfirmJoinBuyIn = false
            }
            activeTable = table
            draftSessionCurrencyCode = table.sessionCurrencyCode
            router.pendingTableInviteCode = nil
            joinCodeText = table.inviteCode
            if table.isHostLocally, hasJoinableBuyIn {
                showingSeatSelection = true
            } else if !table.isHostLocally, shouldAskJoinBuyIn(for: table) {
                await presentJoinBuyInAfterJoin()
            }
        } catch let error as TableRepositoryError where error == .notSignedIn {
            joinError = error.localizedDescription
        } catch {
            joinError = error.localizedDescription
            router.pendingTableInviteCode = nil
        }
    }
}
