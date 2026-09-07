import SwiftUI
import SwiftData

struct MyTablesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \OpenTableModel.updatedAt, order: .reverse) private var tables: [OpenTableModel]
    @State private var activeInviteCode: String?
    @State private var showEditTables = false

    let onTablesChanged: () -> Void

    init(onTablesChanged: @escaping () -> Void = {}) {
        self.onTablesChanged = onTablesChanged
    }

    private var repo: TableRepository { TableRepository(context: context) }

    private var orderedTables: [OpenTableModel] {
        TableOrderStore.ordered(tables)
    }

    private var hostedTables: [OpenTableModel] {
        orderedTables.filter(\.isHostLocally)
    }

    private var joinedTables: [OpenTableModel] {
        orderedTables.filter { !$0.isHostLocally }
    }

    var body: some View {
        NavigationStack {
            List {
                if tables.isEmpty {
                    Section {
                        Text("No tables yet. Create a table on the Table or Circles tab, or join with a table code — no friend request needed.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                }

                if !hostedTables.isEmpty {
                    Section("Tables you host") {
                        ForEach(hostedTables) { table in
                            tableRow(table)
                        }
                    }
                }

                if !joinedTables.isEmpty {
                    Section("Tables you joined") {
                        ForEach(joinedTables) { table in
                            tableRow(table)
                        }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEditTables = true } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.body.weight(.medium))
                            .accessibilityLabel("Edit tables")
                    }
                }
            }
            .sheet(isPresented: $showEditTables) {
                EditTablesSheet(tables: orderedTables, onChange: onTablesChanged)
            }
            .onAppear {
                activeInviteCode = repo.activeInviteCode
            }
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
        return "\(table.inviteCode) · \(seatedText) · \(table.sessionCurrencyCode)"
    }
}
