import SwiftUI
import SwiftData

struct EditTablesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let tables: [OpenTableModel]
    let onTablesChanged: () -> Void

    @State private var orderedIds: [UUID]
    @State private var deletedIds: Set<UUID> = []
    @State private var selectedTableId: UUID?
    @State private var selectedCurrencyTable: OpenTableModel?

    init(tables: [OpenTableModel], onTablesChanged: @escaping () -> Void = {}) {
        self.tables = tables
        self.onTablesChanged = onTablesChanged
        _orderedIds = State(initialValue: tables.map(\.id))
    }

    private var tableById: [UUID: OpenTableModel] {
        Dictionary(uniqueKeysWithValues: tables.map { ($0.id, $0) })
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(orderedIds, id: \.self) { id in
                    if let table = tableById[id] {
                        Button {
                            selectedTableId = id
                        } label: {
                            HStack(spacing: 12) {
                                Text(table.inviteCode)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.muted)
                                    .frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(table.displayTitle)
                                        .foregroundStyle(.primary)
                                    Text("\(table.seats.count) seated · \(MoneyFormatting.currencySymbol(for: table.sessionCurrencyCode)) \(table.sessionCurrencyCode)")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.muted)
                                }
                                Spacer()
                                if selectedTableId == id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppTheme.positive)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onMove(perform: move)
                .onDelete(perform: remove)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Tables")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if
                        let selectedTableId,
                        let table = tableById[selectedTableId],
                        table.isHostLocally
                    {
                        InviteCodeCopyLabel(code: table.inviteCode, style: .headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(AppTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                            .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.cardBorder))

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
                            Label("Share invite", systemImage: "square.and.arrow.up")
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppTheme.card)
                                .foregroundStyle(AppTheme.text)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                                .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.cardBorder))
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: save) {
                        Text("Save")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppTheme.positive)
                            .foregroundStyle(AppTheme.contrastText)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    }
                    .buttonStyle(.plain)

                    Button {
                        guard let selectedTableId, let table = tableById[selectedTableId] else { return }
                        selectedCurrencyTable = table
                    } label: {
                        HStack {
                            Label("Change currency", systemImage: "banknote")
                            Spacer()
                            if let selectedTableId, let table = tableById[selectedTableId] {
                                Text("\(MoneyFormatting.currencySymbol(for: table.sessionCurrencyCode)) \(table.sessionCurrencyCode)")
                            }
                        }
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppTheme.card)
                        .foregroundStyle(selectedTableId == nil ? AppTheme.muted : AppTheme.text)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.cardBorder))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedTableId == nil)
                }
                .padding()
                .background(AppTheme.background)
            }
            .onAppear {
                if selectedTableId == nil {
                    selectedTableId = orderedIds.first
                }
            }
        }
        .presentationBackground(AppTheme.background)
        .sheet(item: $selectedCurrencyTable) { table in
            CurrencyPickerSheet(selectedCurrencyCode: table.sessionCurrencyCode) { code in
                let cleaned = CurrencyPreferences.normalizedCurrencyCode(code)
                guard CurrencyPreferences.isValidCurrencyCode(cleaned) else { return }
                TableRepository(context: context).updateSessionCurrency(on: table, to: cleaned)
                onTablesChanged()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        orderedIds.move(fromOffsets: source, toOffset: destination)
    }

    private func remove(at offsets: IndexSet) {
        for index in offsets {
            deletedIds.insert(orderedIds[index])
        }
        orderedIds.remove(atOffsets: offsets)
    }

    private func save() {
        let repo = TableRepository(context: context)
        let remainingIds = orderedIds
        let removed = tables.filter { deletedIds.contains($0.id) }
        TableOrderStore.save(remainingIds)
        onTablesChanged()
        dismiss()

        Task {
            for table in removed {
                await repo.remove(table)
            }
            onTablesChanged()
        }
    }
}
