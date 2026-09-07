import SwiftUI
import SwiftData

struct EditTablesSheet: View {
    @Environment(\.modelContext) private var context

    let tables: [OpenTableModel]
    let onTablesChanged: () -> Void

    @State private var selectedCurrencyTable: OpenTableModel?

    init(tables: [OpenTableModel], onTablesChanged: @escaping () -> Void = {}) {
        self.tables = tables
        self.onTablesChanged = onTablesChanged
    }

    private var repo: TableRepository { TableRepository(context: context) }

    var body: some View {
        EditOrderedListSheet(
            title: "Edit Tables",
            items: tables,
            id: \.id,
            code: { $0.inviteCode },
            name: { $0.displayTitle },
            subtitle: { table in
                let seated = table.seats.count
                let seatedText = seated == 1 ? "1 seated" : "\(seated) seated"
                let role = table.isHostLocally ? "Host" : "Joined"
                return "\(role) · \(seatedText) · \(MoneyFormatting.currencySymbol(for: table.sessionCurrencyCode)) \(table.sessionCurrencyCode)"
            },
            onSave: save
        ) { selected in
            if let selected, selected.isHostLocally {
                EditOrderedListInviteCard(code: selected.inviteCode)

                EditOrderedListShareButton(
                    url: TableInviteSharing.url(forInviteCode: selected.inviteCode),
                    subject: "Join my Pot Master table",
                    message: TableInviteSharing.message(
                        forInviteCode: selected.inviteCode,
                        hostName: selected.hostDisplayName
                    ),
                    title: "Share table"
                )
            }
        } footer: { selected in
            EditOrderedListCurrencyButton(
                currencyCode: selected?.sessionCurrencyCode,
                isEnabled: selected?.isHostLocally == true
            ) {
                selectedCurrencyTable = selected
            }
        }
        .sheet(item: $selectedCurrencyTable) { table in
            CurrencyPickerSheet(selectedCurrencyCode: table.sessionCurrencyCode) { code in
                let cleaned = CurrencyPreferences.normalizedCurrencyCode(code)
                guard CurrencyPreferences.isValidCurrencyCode(cleaned) else { return }
                repo.updateSessionCurrency(on: table, to: cleaned)
                onTablesChanged()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func save(orderedIds: [UUID], deletedIds: Set<UUID>) async {
        let repo = TableRepository(context: context)
        for id in deletedIds {
            guard let table = tables.first(where: { $0.id == id }) else { continue }
            await repo.remove(table)
        }
        TableOrderStore.save(orderedIds)
        onTablesChanged()
    }
}
