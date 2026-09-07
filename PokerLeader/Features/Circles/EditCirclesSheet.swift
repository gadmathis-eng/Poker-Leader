import SwiftUI
import SwiftData

struct EditCirclesSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    let circles: [CircleModel]
    @State private var selectedCurrencyCircle: CircleModel?

    var body: some View {
        EditOrderedItemsSheet(
            title: "Edit Circles",
            items: circles,
            id: \.id,
            onSave: save
        ) { circle, isSelected in
            EditOrderedItemRow(
                leadingText: circle.shortCode,
                title: circle.name,
                subtitle: "\(circle.memberCount) members · \(MoneyFormatting.currencySymbol(for: circle.currencyCode)) \(circle.currencyCode)",
                isSelected: isSelected
            )
        } footer: { circle in
            VStack(spacing: 12) {
                if let circle, CircleCreatorStore.isCreator(of: circle.id) {
                    EditOrderedItemInviteActions(
                        shareURL: CircleInviteSharing.url(for: circle),
                        subject: "Join \(circle.name) on Pot Master",
                        message: CircleInviteSharing.message(for: circle)
                    )
                }

                Button {
                    selectedCurrencyCircle = circle
                } label: {
                    HStack {
                        Label("Change currency", systemImage: "banknote")
                        Spacer()
                        if let circle {
                            Text("\(MoneyFormatting.currencySymbol(for: circle.currencyCode)) \(circle.currencyCode)")
                        }
                    }
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(AppTheme.card)
                    .foregroundStyle(circle == nil ? AppTheme.muted : AppTheme.text)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.cardBorder))
                }
                .buttonStyle(.plain)
                .disabled(circle == nil)
            }
        }
        .sheet(item: $selectedCurrencyCircle) { circle in
            CircleCurrencySettingsView(circle: circle)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
