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
    @State private var showMyTables = false
    @State private var activeTable: OpenTableModel?
    @State private var joinError: String?
    @State private var joinCodeText = ""
    @State private var isJoiningTable = false
    @State private var showSignIn = false
    @State private var authManager = SupabaseAuthManager.shared

    private var hostedTables: [OpenTableModel] {
        tables.filter(\.isHostLocally)
    }

    private var joinedTables: [OpenTableModel] {
        tables.filter { !$0.isHostLocally }
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
        !TableInviteDeepLink.normalizedCode(joinCodeText).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Live poker")
                        Text("Table")
                            .font(.largeTitle.bold())
                            .foregroundStyle(AppTheme.text)
                        Text("Track your personal buy-in, then share a link so friends can sit down.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                    .padding(.horizontal)

                    if let activeTable, !activeTable.isHostLocally {
                        joiningBanner(activeTable)
                    }

                    if router.pendingTableInviteCode != nil, SupabaseBootstrap.isConfigured, !authManager.isSignedIn {
                        signInToJoinBanner
                    }

                    if let joinError {
                        Text(joinError)
                            .font(.caption)
                            .foregroundStyle(AppTheme.negative)
                            .padding(.horizontal)
                    }

                    yourTablesSection

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Join with code")

                        TextField("Paste table code", text: $joinCodeText)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.headline.monospaced())
                            .padding(14)
                            .background(AppTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                    .stroke(AppTheme.cardBorder)
                            )

                        Button {
                            Task { await joinWithTypedCode() }
                        } label: {
                            Text(isJoiningTable ? "Joining..." : "Join with code")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(canJoinWithTypedCode ? AppTheme.positive : AppTheme.card)
                                .foregroundStyle(canJoinWithTypedCode ? AppTheme.contrastText : AppTheme.muted)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canJoinWithTypedCode || isJoiningTable)
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "New session")

                        DualCurrencyBuyInSetup(
                            sessionCurrencyCode: $draftSessionCurrencyCode,
                            buyInCurrencyCode: $draftBuyInCurrencyCode,
                            buyInText: $draftBuyInText
                        )

                        Button {
                            savePersonalBuyIn()
                        } label: {
                            Text(activeTable?.isHostLocally == false ? "Join table" : "Save buy-in")
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

                    if let amount = personalBuyInAmount, amount > 0 {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Session currency")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.muted)
                                Spacer()
                                Text(tableSessionCurrencyCode)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.text)
                            }

                            Text(MoneyFormatting.plain(amount, currencyCode: personalBuyInCurrencyCode))
                                .font(.title3.bold())
                                .foregroundStyle(AppTheme.gold)
                        }
                        .padding(16)
                        .background(AppTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                .stroke(AppTheme.cardBorder)
                        )
                        .padding(.horizontal)
                    }

                    VStack(spacing: 14) {
                        Image(systemName: "table.furniture.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(AppTheme.text)

                        if let activeTable {
                            if let name = activeTable.name {
                                Text(name)
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.text)
                            }
                            InviteCodeCopyLabel(code: activeTable.inviteCode, style: .headline)
                            Text(tableListSummary(for: activeTable))
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                        } else {
                            Text("No active table")
                                .font(.headline)
                                .foregroundStyle(AppTheme.text)
                        }

                        Text(activeTable == nil
                             ? "Paste a friend's table code above, or set your buy-in and share your own table. Hosted and joined tables are listed under Your tables."
                             : "Open the table to pick a seat, share the code, or tap Edit on a table in Your tables.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                            .multilineTextAlignment(.center)

                        if let activeTable {
                            HStack(spacing: 10) {
                                NavigationLink {
                                    EditTableView(table: activeTable, onChange: handleTablesChanged)
                                } label: {
                                    Label("Edit table", systemImage: "pencil")
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(AppTheme.contrastText)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 10)
                                        .background(AppTheme.positive)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                ShareLink(
                                    item: TableInviteSharing.url(forInviteCode: activeTable.inviteCode),
                                    subject: Text("Join my Pot Master table"),
                                    message: Text(
                                        TableInviteSharing.message(
                                            forInviteCode: activeTable.inviteCode,
                                            hostName: activeTable.hostDisplayName
                                        )
                                    )
                                ) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(AppTheme.contrastText)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 10)
                                        .background(AppTheme.positive)
                                        .clipShape(Capsule())
                                }
                            }
                        }

                        if hasJoinableBuyIn {
                            Button("Open table") {
                                showingSeatSelection = true
                            }
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.contrastText)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(AppTheme.positive)
                            .clipShape(Capsule())
                        }
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
                .padding(.vertical)
            }
            .background(AppTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showMyTables = true } label: {
                        Label("Your tables", systemImage: "list.bullet")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Your tables")
                }
            }
            .onAppear(perform: loadDraftValues)
            .task {
                loadActiveTable()
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
            .sheet(isPresented: $showMyTables, onDismiss: handleTablesChanged) {
                MyTablesSheet(onTablesChanged: handleTablesChanged)
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
                    Task { await handlePendingJoin() }
                }
            }
        }
    }

    private var yourTablesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Your tables")
                Spacer()
                Button("See all") { showMyTables = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.positive)
            }

            if tables.isEmpty {
                Text("Tables you host or join show up here. Save a buy-in below to host one, or paste a friend's code.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            } else {
                if !hostedTables.isEmpty {
                    Text("You host")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                    ForEach(hostedTables) { table in
                        tableSummaryLink(table)
                    }
                }
                if !joinedTables.isEmpty {
                    Text("You joined")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                    ForEach(joinedTables) { table in
                        tableSummaryLink(table)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func tableSummaryLink(_ table: OpenTableModel) -> some View {
        NavigationLink {
            EditTableView(table: table, onChange: handleTablesChanged)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(table.displayTitle)
                            .font(.headline)
                            .foregroundStyle(AppTheme.text)
                            .lineLimit(1)
                        if activeTable?.inviteCode == table.inviteCode {
                            Text("OPEN")
                                .font(.caption2.weight(.bold))
                                .tracking(1)
                                .foregroundStyle(AppTheme.positive)
                        }
                    }
                    Text(tableListSummary(for: table))
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Text("Edit")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.positive)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(14)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.cardBorder)
            )
        }
        .buttonStyle(.plain)
    }

    private func tableListSummary(for table: OpenTableModel) -> String {
        let seated = table.seats.count
        let seatedText = seated == 1 ? "1 seated" : "\(seated) seated"
        let role = table.isHostLocally ? "Host" : "Joined"
        return "\(role) · \(table.inviteCode) · \(seatedText) · \(table.sessionCurrencyCode)"
    }

    private var signInToJoinBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in to join this table")
                .font(.headline)
                .foregroundStyle(AppTheme.text)
            Text("The host shared a link. Use the same Pot Master account on this device, then you'll sit at their table.")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
            Button("Sign in") {
                showSignIn = true
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(AppTheme.contrastText)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppTheme.positive)
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.cardBorder)
        )
        .padding(.horizontal)
    }

    private func joiningBanner(_ table: OpenTableModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("You're joining \(table.hostDisplayName)'s table")
                .font(.headline)
                .foregroundStyle(AppTheme.text)
            Text("Set your buy-in, then pick an open seat.")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.cardBorder)
        )
        .padding(.horizontal)
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
    }

    private func savePersonalBuyIn() {
        guard let amount = draftBuyInAmount else { return }
        personalBuyInCurrencyCode = draftBuyInCurrencyCode
        personalBuyInAmountString = NSDecimalNumber(decimal: amount).stringValue

        if activeTable?.isHostLocally != false {
            personalSessionCurrencyCode = draftSessionCurrencyCode
        }

        if activeTable == nil {
            activeTable = try? repo.ensureHostTable(
                sessionCurrencyCode: draftSessionCurrencyCode,
                hostDisplayName: displayName
            )
        } else if let table = activeTable, table.isHostLocally {
            table.sessionCurrencyCode = draftSessionCurrencyCode
            table.hostDisplayName = displayName
            repo.publish(table)
        }

        if let table = activeTable, table.isHostLocally {
            Task { await publishHostTable(table) }
        }

        showingSeatSelection = true
    }

    private func joinWithTypedCode() async {
        let code = TableInviteDeepLink.normalizedCode(joinCodeText)
        guard !code.isEmpty else { return }

        router.pendingTableInviteCode = code
        await handlePendingJoin()
    }

    private func publishHostTable(_ table: OpenTableModel) async {
        do {
            try await repo.publishForSharing(table)
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
            activeTable = table
            draftSessionCurrencyCode = table.sessionCurrencyCode
            router.pendingTableInviteCode = nil
            joinCodeText = table.inviteCode
            if hasJoinableBuyIn {
                showingSeatSelection = true
            }
        } catch let error as TableRepositoryError where error == .notSignedIn {
            joinError = error.localizedDescription
        } catch {
            joinError = error.localizedDescription
            router.pendingTableInviteCode = nil
        }
    }
}
