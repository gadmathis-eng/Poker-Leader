import SwiftUI
import SwiftData

struct NewSessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @AppStorage("playerHandle") private var playerHandle = "@yourname"
    let circleId: UUID

    @Query private var circles: [CircleModel]
    @State private var title = ""
    @State private var buyInText = "20"
    @State private var playerMoneyTexts: [UUID: String] = [:]
    @State private var selectedMemberIds: Set<UUID> = []
    @State private var savedTitle = ""
    @State private var savedBuyInText = "20"
    @State private var savedPlayerMoneyTexts: [UUID: String] = [:]
    @State private var savedMemberIds: Set<UUID> = []
    @State private var currencyCode = CurrencyPreferences.defaultCurrencyCode
    @State private var savedCurrencyCode = CurrencyPreferences.defaultCurrencyCode
    @State private var savedSetupSession: SessionModel?
    @State private var didLoadSetup = false
    @State private var editingBuyIn: MoneyAmountEditorState?
    @State private var showingCurrencyPicker = false

    private var circle: CircleModel? { circles.first { $0.id == circleId } }
    private var hasUnsavedChanges: Bool {
        title != savedTitle ||
        buyInText != savedBuyInText ||
        currencyCode != savedCurrencyCode ||
        selectedMemberIds != savedMemberIds ||
        selectedPlayerMoneyTexts != savedPlayerMoneyTexts
    }
    private var canPersistSetup: Bool {
        hasUnsavedChanges && isValidSetup
    }
    private var isValidSetup: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        buyInAmount != nil &&
        selectedMemberIds.count >= 2 &&
        selectedPlayerTotals != nil
    }
    private var buyInAmount: Decimal? {
        nonNegativeDecimal(from: buyInText)
    }
    private var selectedPlayerTotals: [UUID: Decimal]? {
        var totals: [UUID: Decimal] = [:]
        for id in selectedMemberIds {
            let text = playerMoneyTexts[id] ?? "0"
            guard let value = nonNegativeDecimal(from: text) else {
                return nil
            }
            totals[id] = value
        }
        return totals
    }
    private var selectedPlayerMoneyTexts: [UUID: String] {
        playerMoneyTexts.filter { selectedMemberIds.contains($0.key) }
    }

    private func titleSuggestions(for circle: CircleModel) -> [String] {
        [circle.name, "The Monthly Robbery", "Boys Night Table"]
    }

    var body: some View {
        Group {
            if let circle {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        SectionHeader(title: "Session setup")
                        Text("New session")
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.text)

                        HStack(spacing: 12) {
                            InviteCodeCopyLabel(code: circle.shortCode)
                            Text(circle.name)
                                .foregroundStyle(AppTheme.text)
                            Spacer(minLength: 0)
                            ShareLink(
                                item: CircleInviteSharing.url(for: circle),
                                subject: Text("Join \(circle.name) on Pot Master"),
                                message: Text(
                                    CircleInviteSharing.sessionSetupMessage(
                                        for: circle,
                                        title: title,
                                        buyInAmount: buyInAmount ?? circle.defaultBuyIn,
                                        currencyCode: currencyCode
                                    )
                                )
                            ) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(AppTheme.contrastText)
                                    .frame(width: 42, height: 42)
                                    .background(AppTheme.positive)
                                    .clipShape(Circle())
                            }
                        }

                        TextField("Session title", text: $title)
                            .textInputAutocapitalization(.words)
                            .padding(16)
                            .background(AppTheme.card)
                            .foregroundStyle(AppTheme.text)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                    .stroke(AppTheme.cardBorder)
                            )

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(titleSuggestions(for: circle), id: \.self) { suggestion in
                                    Button(suggestion) { title = suggestion }
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(title == suggestion ? AppTheme.positive.opacity(0.15) : AppTheme.card)
                                        .clipShape(Capsule())
                                        .foregroundStyle(title == suggestion ? AppTheme.positive : AppTheme.text)
                                }
                            }
                        }

                        SectionHeader(title: "Standard buy-in")
                        StandardBuyInCard(
                                amount: buyInAmount ?? 0,
                                currencyCode: currencyCode,
                                onAmountTap: {
                                    editingBuyIn = MoneyAmountEditorState(
                                        id: circle.id,
                                        title: "Standard buy-in",
                                        subtitle: circle.name,
                                        currencyCode: currencyCode,
                                        text: buyInText
                                    )
                                },
                                onCurrencyTap: {
                                    showingCurrencyPicker = true
                                }
                            )

                        SectionHeader(title: "Usernames · \(selectedMemberIds.count) in")
                        ForEach(circle.members) { member in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 10) {
                                    PlayerAvatarView(initial: member.initial, size: 32)
                                    Text(member.displayName(preferredHandle: playerHandle))
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(AppTheme.text)
                                    Spacer(minLength: 0)
                                    Toggle("", isOn: selectedBinding(for: member))
                                        .labelsHidden()
                                        .tint(AppTheme.positive)
                                }

                                if selectedMemberIds.contains(member.id) {
                                    Divider().overlay(AppTheme.cardBorder)

                                    HStack(spacing: 12) {
                                        Text("Money in")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.muted)

                                        Spacer(minLength: 0)

                                        Button {
                                            removeBuyIn(for: member)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.title2)
                                                .foregroundStyle(AppTheme.negative)
                                        }
                                        .disabled(!canRemoveBuyIn(from: member))

                                        VStack(spacing: 2) {
                                            Text(MoneyFormatting.plain(totalIn(for: member), currencyCode: currencyCode))
                                                .font(.headline)
                                                .foregroundStyle(AppTheme.text)
                                            Text("\(buyInCount(for: member))× buy-in")
                                                .font(.caption2)
                                                .foregroundStyle(AppTheme.muted)
                                        }
                                        .frame(minWidth: 72)

                                        Button {
                                            addBuyIn(for: member)
                                        } label: {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.title2)
                                                .foregroundStyle(AppTheme.positive)
                                        }
                                        .disabled(!canAddBuyIn)
                                    }
                                }
                            }
                            .padding(16)
                            .background(AppTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                    .stroke(AppTheme.cardBorder)
                            )
                        }

                        Button(action: startSession) {
                            Text("Start session →")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppTheme.positive)
                                .foregroundStyle(AppTheme.contrastText)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        }
                        .disabled(!isValidSetup)
                    }
                    .padding()
                }
                .background(AppTheme.background)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save", action: saveSetup)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.positive)
                            .disabled(!canPersistSetup)
                    }
                }
                .onAppear {
                    loadSetupIfNeeded(for: circle)
                    if router.currentUserMemberId == nil {
                        router.currentUserMemberId = circle.members.first(where: \.isCurrentUser)?.id
                    }
                }
                .sheet(item: $editingBuyIn) { editor in
                    MoneyAmountEditorSheet(editor: editor) { text in
                        buyInText = sanitizedNonNegativeDecimalText(text)
                    }
                    .presentationDetents([.height(420)])
                    .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $showingCurrencyPicker) {
                    CurrencyPickerSheet(selectedCurrencyCode: currencyCode) { code in
                        applyCurrencyChange(code, for: circle)
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            } else {
                ContentUnavailableView("Circle not found", systemImage: "exclamationmark.circle")
            }
        }
    }

    private func loadSetupIfNeeded(for circle: CircleModel) {
        guard !didLoadSetup else { return }
        didLoadSetup = true

        let repo = SessionRepository(context: context)
        if let setupSession = repo.setupSession(for: circle) {
            savedSetupSession = setupSession
            title = setupSession.title
            buyInText = decimalText(setupSession.buyInAmount)
            currencyCode = setupSession.currencyCode
            selectedMemberIds = Set(setupSession.players.compactMap(\.memberId))
            playerMoneyTexts = Dictionary(
                uniqueKeysWithValues: setupSession.players.compactMap { player in
                    player.memberId.map { ($0, decimalText(player.totalIn)) }
                }
            )
        } else {
            title = circle.name
            selectedMemberIds = Set(circle.members.filter { $0.initial != "D" }.map(\.id))
            buyInText = decimalText(circle.defaultBuyIn)
            currencyCode = circle.currencyCode
            playerMoneyTexts = Dictionary(uniqueKeysWithValues: selectedMemberIds.map { ($0, "0") })
        }

        savedTitle = title
        savedBuyInText = buyInText
        savedCurrencyCode = currencyCode
        savedMemberIds = selectedMemberIds
        savedPlayerMoneyTexts = selectedPlayerMoneyTexts
    }

    private func applyCurrencyChange(_ code: String, for circle: CircleModel) {
        let cleanedCode = CurrencyPreferences.normalizedCurrencyCode(code)
        guard CurrencyPreferences.isValidCurrencyCode(cleanedCode) else { return }

        currencyCode = cleanedCode
        circle.currencyCode = cleanedCode
        savedSetupSession?.currencyCode = cleanedCode
        try? context.save()

        Task {
            try? await SupabaseSyncService.shared.upsertCircle(circle)
            if let savedSetupSession {
                try? await SupabaseSyncService.shared.upsertSession(savedSetupSession)
            }
        }
    }

    private var canAddBuyIn: Bool {
        buyInAmount.map { $0 > 0 } ?? false
    }

    private func saveSetup() {
        guard let circle, let buyInAmount, let selectedPlayerTotals else { return }
        let members = selectedMembers(in: circle)
        let repo = SessionRepository(context: context)
        let session = repo.saveSetupSession(
            existing: savedSetupSession,
            circle: circle,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            buyInAmount: buyInAmount,
            currencyCode: currencyCode,
            playerMembers: members,
            playerTotals: selectedPlayerTotals
        )
        savedSetupSession = session
        title = session.title
        buyInText = decimalText(session.buyInAmount)
        currencyCode = session.currencyCode
        playerMoneyTexts = moneyTexts(from: session)
        savedTitle = session.title
        savedBuyInText = buyInText
        savedCurrencyCode = currencyCode
        savedMemberIds = selectedMemberIds
        savedPlayerMoneyTexts = selectedPlayerMoneyTexts
    }

    private func startSession() {
        guard let circle, let buyInAmount, let selectedPlayerTotals else { return }
        let members = selectedMembers(in: circle)
        let repo = SessionRepository(context: context)
        let session = repo.saveSetupSession(
            existing: savedSetupSession,
            circle: circle,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            buyInAmount: buyInAmount,
            currencyCode: currencyCode,
            playerMembers: members,
            playerTotals: selectedPlayerTotals
        )
        repo.start(session: session)
        savedSetupSession = session
        savedTitle = session.title
        buyInText = decimalText(session.buyInAmount)
        currencyCode = session.currencyCode
        playerMoneyTexts = moneyTexts(from: session)
        savedBuyInText = decimalText(session.buyInAmount)
        savedCurrencyCode = currencyCode
        savedMemberIds = selectedMemberIds
        savedPlayerMoneyTexts = selectedPlayerMoneyTexts
        router.push(.liveTable(session.id))
    }

    private func selectedMembers(in circle: CircleModel) -> [MemberModel] {
        circle.members.filter { selectedMemberIds.contains($0.id) }
    }

    private func selectedBinding(for member: MemberModel) -> Binding<Bool> {
        Binding(
            get: { selectedMemberIds.contains(member.id) },
            set: { isSelected in
                if isSelected {
                    selectedMemberIds.insert(member.id)
                    if playerMoneyTexts[member.id] == nil {
                        playerMoneyTexts[member.id] = "0"
                    }
                } else {
                    selectedMemberIds.remove(member.id)
                }
            }
        )
    }

    private func addBuyIn(for member: MemberModel) {
        guard let buyInAmount, buyInAmount > 0 else { return }
        let current = nonNegativeDecimal(from: playerMoneyTexts[member.id] ?? "0") ?? 0
        playerMoneyTexts[member.id] = decimalText(current + buyInAmount)
    }

    private func removeBuyIn(for member: MemberModel) {
        guard let buyInAmount, buyInAmount > 0 else { return }
        let current = nonNegativeDecimal(from: playerMoneyTexts[member.id] ?? "0") ?? 0
        playerMoneyTexts[member.id] = decimalText((current - buyInAmount).clampedToNonNegative)
    }

    private func canRemoveBuyIn(from member: MemberModel) -> Bool {
        guard let buyInAmount, buyInAmount > 0 else { return false }
        return (nonNegativeDecimal(from: playerMoneyTexts[member.id] ?? "0") ?? 0) > 0
    }

    private func totalIn(for member: MemberModel) -> Decimal {
        nonNegativeDecimal(from: playerMoneyTexts[member.id] ?? "0") ?? 0
    }

    private func buyInCount(for member: MemberModel) -> Int {
        guard let buyInAmount, buyInAmount > 0 else { return 0 }
        let rawCount = NSDecimalNumber(decimal: totalIn(for: member) / buyInAmount)
        return max(0, rawCount.rounding(accordingToBehavior: nil).intValue)
    }

    private func moneyTexts(from session: SessionModel) -> [UUID: String] {
        Dictionary(
            uniqueKeysWithValues: session.players.compactMap { player in
                player.memberId.map { ($0, decimalText(player.totalIn)) }
            }
        )
    }

    private func decimalText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private func nonNegativeDecimal(from text: String) -> Decimal? {
        Decimal(string: text.trimmingCharacters(in: .whitespacesAndNewlines))?.clampedToNonNegative
    }

    private func sanitizedNonNegativeDecimalText(_ text: String) -> String {
        if text.contains("-") { return "0" }
        guard let value = Decimal(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return text
        }
        return value < 0 ? "0" : text
    }
}
