import SwiftUI
import SwiftData

struct EditCirclesSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    let circles: [CircleModel]
    @State private var selectedCurrencyCircle: CircleModel?

    var body: some View {
        EditOrderedListSheet(
            title: "Edit Circles",
            items: circles,
            id: \.id,
            code: { $0.shortCode },
            name: { $0.name },
            subtitle: { circle in
                "\(circle.memberCount) members · \(MoneyFormatting.currencySymbol(for: circle.currencyCode)) \(circle.currencyCode)"
            },
            onSave: save
        ) { selected in
            if let selected, CircleCreatorStore.isCreator(of: selected.id) {
                EditOrderedListInviteCard(code: selected.shortCode)

                EditOrderedListShareButton(
                    url: CircleInviteSharing.url(for: selected),
                    subject: "Join \(selected.name) on Pot Master",
                    message: CircleInviteSharing.message(for: selected)
                )
            }
        } footer: { selected in
            EditOrderedListCurrencyButton(
                currencyCode: selected?.currencyCode,
                isEnabled: selected != nil
            ) {
                selectedCurrencyCircle = selected
            }
        }
        .sheet(item: $selectedCurrencyCircle) { circle in
            CircleCurrencySettingsView(circle: circle)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func save(orderedIds: [UUID], deletedIds: Set<UUID>) async {
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
