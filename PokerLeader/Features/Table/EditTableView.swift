import SwiftUI
import SwiftData

struct EditTableView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private let table: OpenTableModel
    private let onChange: () -> Void
    private let inviteCode: String
    private let hostName: String
    private let isHost: Bool

    @State private var name: String
    @State private var currencyCode: String
    @State private var seatNumber: Int?
    @State private var seatAmount: Decimal = 0
    @State private var activeInviteCode: String?
    @State private var showCurrencyPicker = false
    @State private var showRemoveConfirmation = false
    @State private var isRemoving = false
    @State private var isDealtIn = false

    init(table: OpenTableModel, onChange: @escaping () -> Void = {}) {
        self.table = table
        self.onChange = onChange
        self.inviteCode = table.inviteCode
        self.hostName = table.hostDisplayName
        self.isHost = table.isHostLocally
        _name = State(initialValue: table.name ?? "")
        _currencyCode = State(initialValue: table.sessionCurrencyCode)
    }

    private var repo: TableRepository { TableRepository(context: context) }

    private var isActive: Bool {
        activeInviteCode == inviteCode
    }

    private var hostLabel: String {
        if isHost { return "You" }
        let trimmed = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        return MemberModel.isPlaceholderName(trimmed) ? "Table host" : trimmed
    }

    private var currencyLabel: String {
        "\(MoneyFormatting.currencySymbol(for: currencyCode)) \(currencyCode)"
    }

    private var removeActionTitle: String {
        isHost ? "Delete table" : "Leave table"
    }

    private var removeConfirmationTitle: String {
        isHost ? "Delete this table?" : "Leave this table?"
    }

    var body: some View {
        Form {
            Section {
                TextField("Table name", text: $name)
            } header: {
                Text("Name")
            } footer: {
                Text("Only you see this name. Tables without one show their code.")
            }

            Section("Table") {
                LabeledContent("Code") {
                    InviteCodeCopyLabel(code: inviteCode)
                }
                LabeledContent("Host", value: hostLabel)
                if isHost {
                    Button { showCurrencyPicker = true } label: {
                        editableRow(title: "Currency", value: currencyLabel, valueColor: AppTheme.text)
                    }
                    .buttonStyle(.plain)
                } else {
                    LabeledContent("Currency", value: currencyLabel)
                }
            }

            Section {
                if let seatNumber {
                    LabeledContent("Seat", value: "Seat \(seatNumber)")
                    LabeledContent("Money in") {
                        Text(MoneyFormatting.plain(seatAmount, currencyCode: currencyCode))
                            .foregroundStyle(AppTheme.gold)
                    }
                } else {
                    Text("You haven't taken a seat here yet. Open the table to sit down.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
            } header: {
                Text("Your seat")
            } footer: {
                if seatNumber != nil {
                    Text(isDealtIn
                         ? "This is your buy-in. You are in a hand, so it changes again once the pot is settled."
                         : "This is your buy-in. It cannot be changed after you sit down.")
                }
            }

            Section {
                if isActive {
                    Label("Open on the Table tab", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.positive)
                } else {
                    Button("Open this table on the Table tab", action: makeActive)
                }

                ShareLink(
                    item: TableInviteSharing.url(forInviteCode: inviteCode),
                    subject: Text("Join my Pot Master table"),
                    message: Text(TableInviteSharing.message(forInviteCode: inviteCode, hostName: hostName))
                ) {
                    Label("Share table", systemImage: "square.and.arrow.up")
                }
            }

            Section {
                Button(role: .destructive) {
                    showRemoveConfirmation = true
                } label: {
                    Text(removeActionTitle)
                }
                .disabled(isRemoving)
            } footer: {
                Text(isHost
                     ? "Deleting closes the table for everyone who joined with your link."
                     : "Leaving frees your seat and removes the table from this device.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Edit table")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(isRemoving)
            }
        }
        .onAppear(perform: loadTableState)
        .sheet(isPresented: $showCurrencyPicker) {
            CurrencyPickerSheet(selectedCurrencyCode: currencyCode) { code in
                let cleaned = CurrencyPreferences.normalizedCurrencyCode(code)
                guard CurrencyPreferences.isValidCurrencyCode(cleaned) else { return }
                currencyCode = cleaned
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            removeConfirmationTitle,
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button(removeActionTitle, role: .destructive, action: remove)
            Button("Cancel", role: .cancel) {}
        }
    }

    private func editableRow(title: String, value: String, valueColor: Color) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(AppTheme.text)
            Spacer()
            Text(value)
                .foregroundStyle(valueColor)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
        }
        .contentShape(Rectangle())
    }

    private func loadTableState() {
        activeInviteCode = repo.activeInviteCode
        isDealtIn = repo.isDealtIn(table)

        guard let seat = repo.mySeat(on: table) else {
            seatNumber = nil
            seatAmount = 0
            return
        }

        seatNumber = seat.seatNumber
        seatAmount = seat.amountDecimal.clampedToNonNegative
    }

    private func makeActive() {
        repo.makeActive(table)
        activeInviteCode = repo.activeInviteCode
        onChange()
    }

    private func save() {
        let repo = self.repo
        repo.rename(table, to: name)

        if isHost {
            repo.updateSessionCurrency(on: table, to: currencyCode)
        }

        onChange()
        dismiss()
    }

    private func remove() {
        guard !isRemoving else { return }
        isRemoving = true

        let repo = self.repo
        let target = table
        let notifyChange = onChange
        dismiss()

        Task {
            await repo.remove(target)
            notifyChange()
        }
    }
}
