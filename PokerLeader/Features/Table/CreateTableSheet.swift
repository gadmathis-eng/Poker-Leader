import SwiftUI
import SwiftData

struct CreateTableSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @AppStorage("displayName") private var displayName = "Your name"
    @AppStorage("personalSessionCurrencyCode") private var personalSessionCurrencyCode = CurrencyPreferences.defaultCurrencyCode
    @AppStorage("personalBuyInCurrencyCode") private var personalBuyInCurrencyCode = CurrencyPreferences.defaultCurrencyCode
    @AppStorage("personalBuyInAmount") private var personalBuyInAmountString = ""

    @State private var tableCurrencyCode: String
    @State private var payInCurrencyCode: String
    @State private var buyInText: String
    @State private var anteText: String
    @State private var didEditAnte = false
    @State private var currencyPickerTarget: DualCurrencyPickerTarget?
    @State private var editingAmount: CreateTableAmountEditor?
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showSignIn = false
    @State private var authManager = SupabaseAuthManager.shared

    init() {
        let tableCurrency = UserDefaults.standard.string(forKey: "personalSessionCurrencyCode")
            ?? CurrencyPreferences.defaultCurrencyCode
        let payInCurrency = UserDefaults.standard.string(forKey: "personalBuyInCurrencyCode")
            ?? CurrencyPreferences.defaultCurrencyCode
        let storedBuyIn = UserDefaults.standard.string(forKey: "personalBuyInAmount") ?? ""
        let buyIn = storedBuyIn.isEmpty ? "20" : storedBuyIn
        let buyInAmount = Decimal(string: buyIn)?.clampedToNonNegative ?? 20
        let tableBuyIn = TableCurrencyConversion.amountInTableCurrency(
            buyInAmount,
            from: payInCurrency,
            to: tableCurrency
        )

        _tableCurrencyCode = State(initialValue: tableCurrency)
        _payInCurrencyCode = State(initialValue: payInCurrency)
        _buyInText = State(initialValue: buyIn)
        _anteText = State(initialValue: TableMoney.string(TableAnte.defaultAmount(forBuyIn: tableBuyIn)))
    }

    private var buyInAmount: Decimal? {
        Decimal(string: buyInText.trimmingCharacters(in: .whitespacesAndNewlines))?.clampedToNonNegative
    }

    private var anteAmount: Decimal? {
        Decimal(string: anteText.trimmingCharacters(in: .whitespacesAndNewlines))?.clampedToNonNegative
    }

    private var tableBuyInAmount: Decimal {
        TableCurrencyConversion.amountInTableCurrency(
            buyInAmount ?? 0,
            from: payInCurrencyCode,
            to: tableCurrencyCode
        )
    }

    private var canCreate: Bool {
        (buyInAmount ?? 0) > 0 &&
        anteAmount != nil &&
        CurrencyPreferences.isValidCurrencyCode(tableCurrencyCode) &&
        CurrencyPreferences.isValidCurrencyCode(payInCurrencyCode) &&
        !isCreating
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    tableCurrencyRow

                    StandardBuyInCard(
                        title: "Buy-in",
                        amount: buyInAmount ?? 0,
                        currencyCode: payInCurrencyCode,
                        onAmountTap: presentPayInEditor,
                        onCurrencyTap: { currencyPickerTarget = .buyIn }
                    )

                    if payInCurrencyCode != tableCurrencyCode, (buyInAmount ?? 0) > 0 {
                        Text("That's \(MoneyFormatting.plain(tableBuyInAmount, currencyCode: tableCurrencyCode)) on the table.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }

                    AnteEditorRow(
                        amount: anteAmount ?? 0,
                        currencyCode: tableCurrencyCode,
                        action: presentAnteEditor
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                            .stroke(AppTheme.cardBorder)
                    )

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(AppTheme.negative)
                    }
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle("Create table")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Creating..." : "Create") {
                        Task { await createTable() }
                    }
                    .disabled(!canCreate)
                }
            }
            .sheet(item: $currencyPickerTarget) { target in
                CurrencyPickerSheet(
                    selectedCurrencyCode: target == .session ? tableCurrencyCode : payInCurrencyCode
                ) { code in
                    let cleaned = CurrencyPreferences.normalizedCurrencyCode(code)
                    guard CurrencyPreferences.isValidCurrencyCode(cleaned) else { return }
                    switch target {
                    case .session:
                        tableCurrencyCode = cleaned
                    case .buyIn:
                        payInCurrencyCode = cleaned
                    }
                    refreshAnteIfNeeded()
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $editingAmount) { editor in
                MoneyAmountEditorSheet(editor: editor.state) { text in
                    switch editor {
                    case .payIn:
                        buyInText = text
                        refreshAnteIfNeeded()
                    case .ante:
                        anteText = text
                        didEditAnte = true
                    }
                }
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $showSignIn) {
                SignInSheet()
                    .modelContext(context)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: authManager.isSignedIn) { _, signedIn in
                if signedIn {
                    showSignIn = false
                    errorMessage = nil
                }
            }
        }
    }

    private var tableCurrencyRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Table currency")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.text)
                    Text("The money the pot and the ante are in")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                CurrencyChipButton(currencyCode: tableCurrencyCode) {
                    currencyPickerTarget = .session
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.cardBorder)
            )
        }
    }

    private func presentPayInEditor() {
        editingAmount = .payIn(
            MoneyAmountEditorState(
                id: UUID(),
                title: "Buy-in",
                subtitle: "What you sit down with",
                currencyCode: payInCurrencyCode,
                text: buyInText
            )
        )
    }

    private func presentAnteEditor() {
        editingAmount = .ante(
            MoneyAmountEditorState(
                id: UUID(),
                title: "Ante",
                subtitle: "In \(tableCurrencyCode)",
                currencyCode: tableCurrencyCode,
                text: anteText.isEmpty ? "0" : anteText,
                maximum: tableBuyInAmount > 0 ? tableBuyInAmount : nil
            )
        )
    }

    private func refreshAnteIfNeeded() {
        guard !didEditAnte else { return }
        anteText = TableMoney.string(TableAnte.defaultAmount(forBuyIn: tableBuyInAmount))
    }

    private func createTable() async {
        guard let buyInAmount, buyInAmount > 0, let anteAmount else { return }

        if SupabaseBootstrap.isConfigured, !authManager.isSignedIn {
            errorMessage = TableRepositoryError.notSignedIn.localizedDescription
            showSignIn = true
            return
        }

        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        personalSessionCurrencyCode = tableCurrencyCode
        personalBuyInCurrencyCode = payInCurrencyCode
        personalBuyInAmountString = NSDecimalNumber(decimal: buyInAmount).stringValue

        do {
            let repo = TableRepository(context: context)
            let table = try repo.startHostedTable(
                name: nil,
                sessionCurrencyCode: tableCurrencyCode,
                hostDisplayName: displayName,
                anteAmount: anteAmount
            )
            do {
                try await repo.publishForSharing(table)
            } catch {
                // The table is on this phone either way; sharing retries from the Table tab.
            }
            router.pendingTableInviteCode = table.inviteCode
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum CreateTableAmountEditor: Identifiable {
    case payIn(MoneyAmountEditorState)
    case ante(MoneyAmountEditorState)

    var id: UUID {
        switch self {
        case .payIn(let state), .ante(let state):
            return state.id
        }
    }

    var state: MoneyAmountEditorState {
        switch self {
        case .payIn(let state), .ante(let state):
            return state
        }
    }
}
