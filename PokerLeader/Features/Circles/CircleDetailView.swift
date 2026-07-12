import SwiftUI
import SwiftData

struct CircleDetailView: View {
    @Environment(AppRouter.self) private var router
    @AppStorage("playerHandle") private var playerHandle = "@yourname"
    let circleId: UUID

    @Query private var circles: [CircleModel]
    @State private var showCircleSettings = false

    private var circle: CircleModel? { circles.first { $0.id == circleId } }

    var body: some View {
        Group {
            if let circle {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            InviteCodeCopyLabel(code: circle.shortCode)
                            Text(circle.name)
                                .font(.title2.bold())
                        }
                        .foregroundStyle(AppTheme.text)

                        Text("\(circle.memberCount) members · \(circle.gameCount) games")
                            .foregroundStyle(AppTheme.muted)

                        if CircleCreatorStore.isCreator(of: circle.id) {
                            creatorInviteCard(circle)
                        }

                        SectionHeader(title: "Members")
                        ForEach(circle.members) { member in
                            Button {
                                router.push(.playerProfile(member.id))
                            } label: {
                                let displayName = member.displayName(preferredHandle: playerHandle)
                                HStack {
                                    PlayerAvatarView(initial: member.initial, size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(displayName)
                                        if let handle = MemberModel.normalizedHandle(member.handle) {
                                            Text(handle)
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.muted)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(AppTheme.muted)
                                }
                                .foregroundStyle(AppTheme.text)
                                .padding()
                                .background(AppTheme.card)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                            }
                            .buttonStyle(.plain)
                        }

                        changeCurrencyButton(for: circle)
                    }
                    .padding()
                }
                .background(AppTheme.background)
                .navigationTitle(circle.name)
                .sheet(isPresented: $showCircleSettings) {
                    CircleCurrencySettingsView(circle: circle)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            } else {
                ContentUnavailableView("Circle not found", systemImage: "person.3")
            }
        }
    }

    private func changeCurrencyButton(for circle: CircleModel) -> some View {
        Button {
            showCircleSettings = true
        } label: {
            HStack {
                Label("Change currency", systemImage: "banknote")
                    .font(.headline.weight(.semibold))
                Spacer()
                Text("\(MoneyFormatting.currencySymbol(for: circle.currencyCode)) \(circle.currencyCode)")
                    .font(.headline.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(AppTheme.card)
            .foregroundStyle(AppTheme.text)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.cardBorder))
        }
        .buttonStyle(.plain)
    }

    private func creatorInviteCard(_ circle: CircleModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Creator invite")

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    InviteCodeCopyLabel(code: circle.shortCode, style: .headline)
                    Text("Tap to copy the code, or share the invite link.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer()

                ShareLink(
                    item: CircleInviteSharing.url(for: circle),
                    subject: Text("Join \(circle.name) on Pot Master"),
                    message: Text(CircleInviteSharing.message(for: circle))
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.contrastText)
                        .frame(width: 42, height: 42)
                        .background(AppTheme.positive)
                        .clipShape(Circle())
                }
            }
            .padding()
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.cardBorder))
        }
    }

}

struct CircleCurrencySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let circle: CircleModel

    @State private var draftCurrencyCode: String
    @State private var searchText = ""
    @State private var currencyMessage: String?

    private var filteredCurrencyOptions: [CurrencyPreference] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return CurrencyPreferences.options }

        return CurrencyPreferences.options.filter { option in
            option.currencyCode.localizedCaseInsensitiveContains(query) ||
            option.currencyName.localizedCaseInsensitiveContains(query) ||
            option.countryName.localizedCaseInsensitiveContains(query)
        }
    }

    private var canSaveCurrency: Bool {
        let cleanedCurrencyCode = CurrencyPreferences.normalizedCurrencyCode(draftCurrencyCode)
        return CurrencyPreferences.isValidCurrencyCode(cleanedCurrencyCode) && cleanedCurrencyCode != circle.currencyCode
    }

    init(circle: CircleModel) {
        self.circle = circle
        self._draftCurrencyCode = State(initialValue: circle.currencyCode)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(circle.name)
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.text)
                        Text("Choose the currency used only for this circle's new and active sessions.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }

                    TextField("Currency code (e.g. USD, ILS, JPY)", text: $draftCurrencyCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding()
                        .background(AppTheme.card)
                        .foregroundStyle(AppTheme.text)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        .onChange(of: draftCurrencyCode) { _, newValue in
                            draftCurrencyCode = CurrencyPreferences.normalizedCurrencyCode(newValue)
                            currencyMessage = nil
                        }

                    TextField("Search every world currency", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(AppTheme.card)
                        .foregroundStyle(AppTheme.text)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

                    Button {
                        updateCurrency()
                    } label: {
                        Text("Save")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canSaveCurrency ? AppTheme.positive : AppTheme.card)
                            .foregroundStyle(canSaveCurrency ? AppTheme.contrastText : AppTheme.muted)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    }
                    .disabled(!canSaveCurrency)
                    .buttonStyle(.plain)

                    if let currencyMessage {
                        Text(currencyMessage)
                            .font(.caption)
                            .foregroundStyle(currencyMessage == "Currency updated." ? AppTheme.positive : AppTheme.negative)
                    }

                    currencyOptionsList
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle("Change currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.muted)
                }
            }
        }
    }

    private var currencyOptionsList: some View {
        PaginatedCurrencyList(
            options: filteredCurrencyOptions,
            selectedCurrencyCode: draftCurrencyCode
        ) { option, isLast in
            Button {
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

    private func updateCurrency() {
        let cleanedCurrencyCode = CurrencyPreferences.normalizedCurrencyCode(draftCurrencyCode)
        guard CurrencyPreferences.isValidCurrencyCode(cleanedCurrencyCode) else {
            currencyMessage = "Use a valid 3-letter ISO currency code, like USD or JPY."
            return
        }

        circle.currencyCode = cleanedCurrencyCode
        for session in circle.sessions where session.status != .settled {
            session.currencyCode = cleanedCurrencyCode
        }

        try? context.save()
        currencyMessage = "Currency updated."

        Task {
            try? await SupabaseSyncService.shared.upsertCircle(circle)
            for session in circle.sessions where session.status != .settled {
                try? await SupabaseSyncService.shared.upsertSession(session)
            }
        }
    }
}
