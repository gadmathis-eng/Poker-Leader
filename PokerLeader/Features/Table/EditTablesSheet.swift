import SwiftUI
import SwiftData

struct EditTablesSheet: View {
    @Environment(\.modelContext) private var context

    let tables: [OpenTableModel]
    let onChange: () -> Void

    var body: some View {
        EditOrderedItemsSheet(
            title: "Edit Tables",
            items: tables,
            id: \.id,
            onSave: save
        ) { table in
            EditOrderedItemRow(
                leadingText: table.inviteCode,
                title: table.displayTitle,
                subtitle: summary(for: table)
            )
        }
    }

    private func summary(for table: OpenTableModel) -> String {
        let seated = table.seats.count
        let seatedText = seated == 1 ? "1 seated" : "\(seated) seated"
        let role = table.isHostLocally ? "You host" : "You joined"
        return "\(role) · \(seatedText) · \(table.sessionCurrencyCode)"
    }

    private func save(orderedIds: [UUID], deletedIds: Set<UUID>) {
        TableOrderStore.save(orderedIds)
        onChange()

        guard !deletedIds.isEmpty else { return }

        Task {
            let repo = TableRepository(context: context)
            for id in deletedIds {
                guard let table = try? repo.fetch(id: id) else { continue }
                await repo.remove(table)
            }
            onChange()
        }
    }
}
