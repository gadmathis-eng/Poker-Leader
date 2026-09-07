import SwiftUI
import SwiftData

struct EditCirclesSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    let circles: [CircleModel]

    var body: some View {
        EditOrderedItemsSheet(
            title: "Edit Circles",
            items: circles,
            id: \.id,
            onSave: save
        ) { circle in
            EditOrderedItemRow(
                leadingText: circle.shortCode,
                title: circle.name,
                subtitle: "\(circle.memberCount) members · \(MoneyFormatting.currencySymbol(for: circle.currencyCode)) \(circle.currencyCode)"
            )
        }
    }

    private func save(orderedIds: [UUID], deletedIds: Set<UUID>) {
        let repo = CircleRepository(context: context)
        for id in deletedIds {
            guard let circle = try? repo.fetch(id: id) else { continue }
            repo.delete(circle)
            if router.selectedCircleId == id {
                router.selectedCircleId = orderedIds.first
            }
        }
        CircleOrderStore.save(orderedIds)
    }
}
