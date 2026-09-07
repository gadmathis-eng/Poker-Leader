import SwiftUI
import SwiftData

struct MyTablesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \OpenTableModel.updatedAt, order: .reverse) private var tables: [OpenTableModel]
    @State private var orderedIds: [UUID] = []
    @State private var activeInviteCode: String?
    @State private var tablesPendingRemoval: [OpenTableModel] = []
    @State private var showRemoveConfirmation = false
    @State private var isRemoving = false

    let onTablesChanged: () -> Void

    init(onTablesChanged: @escaping () -> Void = {}) {
        self.onTablesChanged = onTablesChanged
    }

    private var repo: TableRepository { TableRepository(context: context) }

    private var tableById: [UUID: OpenTableModel] {
        Dictionary(uniqueKeysWithValues: tables.map { ($0.id, $0) })
    }

    private var orderedTables: [OpenTableModel] {
        orderedIds.compactMap { tableById[$0] }
    }

    private var removeActionTitle: String {
        Self.removeActionTitle(for: tablesPendingRemoval)
    }

    private var removeConfirmationTitle: String {
        Self.removeConfirmationTitle(for: tablesPendingRemoval)
    }

    var body: some View {
        NavigationStack {
            List {
                if tables.isEmpty {
                    Section {
                        Text("No tables yet. Create a table on the Table or Circles tab, or join a friend's table with their code.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                } else {
                    Section {
                        ForEach(orderedTables) { table in
                            tableRow(table)
                                .moveDisabled(orderedTables.count < 2)
                        }
                        .onMove(perform: move)
                        .onDelete(perform: requestRemove)
                    } footer: {
                        Text("Swipe to delete a table you host, or leave one you joined. Tap Edit to reorder.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Your Tables")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !tables.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        EditButton()
                    }
                }
            }
            .onAppear {
                activeInviteCode = repo.activeInviteCode
                syncOrder(reset: true)
            }
            .onChange(of: tables.map(\.id)) { _, _ in
                syncOrder()
            }
            .confirmationDialog(
                removeConfirmationTitle,
                isPresented: $showRemoveConfirmation,
                titleVisibility: .visible
            ) {
                Button(removeActionTitle, role: .destructive) {
                    Task { await confirmRemoval() }
                }
                Button("Cancel", role: .cancel, action: cancelRemoval)
            } message: {
                Text(Self.removeConfirmationMessage(for: tablesPendingRemoval))
            }
            .disabled(isRemoving)
        }
        .presentationBackground(AppTheme.background)
    }

    private func tableRow(_ table: OpenTableModel) -> some View {
        NavigationLink {
            EditTableView(table: table, onChange: onTablesChanged)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(table.displayTitle)
                        .foregroundStyle(AppTheme.text)
                        .lineLimit(1)
                    if activeInviteCode == table.inviteCode {
                        Text("OPEN")
                            .font(.caption2.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(AppTheme.positive)
                    }
                }
                Text(summary(for: table))
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
        }
    }

    private func summary(for table: OpenTableModel) -> String {
        let seated = table.seats.count
        let seatedText = seated == 1 ? "1 seated" : "\(seated) seated"
        let role = table.isHostLocally ? "Host" : "Joined"
        return "\(role) · \(table.inviteCode) · \(seatedText) · \(table.sessionCurrencyCode)"
    }

    private func syncOrder(reset: Bool = false) {
        let pendingIds = Set(tablesPendingRemoval.map(\.id))
        if reset || orderedIds.isEmpty {
            orderedIds = TableOrderStore.ordered(tables)
                .map(\.id)
                .filter { !pendingIds.contains($0) }
            return
        }

        let current = Set(tables.map(\.id))
        orderedIds.removeAll { !current.contains($0) || pendingIds.contains($0) }
        let existing = Set(orderedIds)
        let newcomers = TableOrderStore.ordered(tables)
            .map(\.id)
            .filter { !existing.contains($0) && !pendingIds.contains($0) }
        orderedIds = newcomers + orderedIds
    }

    private func move(from source: IndexSet, to destination: Int) {
        orderedIds.move(fromOffsets: source, toOffset: destination)
        TableOrderStore.save(orderedIds)
        onTablesChanged()
    }

    private func requestRemove(at offsets: IndexSet) {
        tablesPendingRemoval = offsets.map { orderedTables[$0] }
        orderedIds.remove(atOffsets: offsets)
        showRemoveConfirmation = true
    }

    private func cancelRemoval() {
        tablesPendingRemoval = []
        syncOrder(reset: true)
    }

    private func confirmRemoval() async {
        guard !isRemoving else { return }
        let pending = tablesPendingRemoval
        guard !pending.isEmpty else { return }

        isRemoving = true
        defer {
            isRemoving = false
            tablesPendingRemoval = []
        }

        for table in pending {
            await repo.remove(table)
        }
        TableOrderStore.save(orderedIds)
        activeInviteCode = repo.activeInviteCode
        onTablesChanged()
    }

    static func removeActionTitle(for tables: [OpenTableModel]) -> String {
        if tables.count > 1 {
            if tables.allSatisfy(\.isHostLocally) { return "Delete tables" }
            if tables.allSatisfy({ !$0.isHostLocally }) { return "Leave tables" }
            return "Remove tables"
        }
        return tables.first?.isHostLocally == true ? "Delete table" : "Leave table"
    }

    static func removeConfirmationTitle(for tables: [OpenTableModel]) -> String {
        if tables.count > 1 {
            if tables.allSatisfy(\.isHostLocally) { return "Delete these tables?" }
            if tables.allSatisfy({ !$0.isHostLocally }) { return "Leave these tables?" }
            return "Remove these tables?"
        }
        return tables.first?.isHostLocally == true ? "Delete this table?" : "Leave this table?"
    }

    static func removeConfirmationMessage(for tables: [OpenTableModel]) -> String {
        if tables.count > 1 {
            if tables.allSatisfy(\.isHostLocally) {
                return "Deleting closes each table for everyone who joined with your link."
            }
            if tables.allSatisfy({ !$0.isHostLocally }) {
                return "Leaving frees your seats and removes these tables from this device."
            }
            return "Tables you host will close for everyone. Tables you joined will free your seat and leave this device."
        }
        if tables.first?.isHostLocally == true {
            return "Deleting closes the table for everyone who joined with your link."
        }
        return "Leaving frees your seat and removes the table from this device."
    }
}
