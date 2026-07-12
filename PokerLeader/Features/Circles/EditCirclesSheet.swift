import SwiftUI
import SwiftData

struct EditCirclesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    let circles: [CircleModel]
    @State private var orderedIds: [UUID]
    @State private var deletedIds: Set<UUID> = []
    @State private var selectedCircleId: UUID?
    @State private var selectedCurrencyCircle: CircleModel?

    init(circles: [CircleModel]) {
        self.circles = circles
        _orderedIds = State(initialValue: circles.map(\.id))
    }

    private var circleById: [UUID: CircleModel] {
        Dictionary(uniqueKeysWithValues: circles.map { ($0.id, $0) })
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(orderedIds, id: \.self) { id in
                    if let circle = circleById[id] {
                        Button {
                            selectedCircleId = id
                        } label: {
                            HStack(spacing: 12) {
                                Text(circle.shortCode)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.muted)
                                    .frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(circle.name)
                                        .foregroundStyle(.primary)
                                    Text("\(circle.memberCount) members · \(MoneyFormatting.currencySymbol(for: circle.currencyCode)) \(circle.currencyCode)")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.muted)
                                }
                                Spacer()
                                if selectedCircleId == id {
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
            .navigationTitle("Edit Circles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if
                        let selectedCircleId,
                        let circle = circleById[selectedCircleId],
                        CircleCreatorStore.isCreator(of: selectedCircleId)
                    {
                        InviteCodeCopyLabel(code: circle.shortCode, style: .headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(AppTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                            .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.cardBorder))

                        ShareLink(
                            item: CircleInviteSharing.url(for: circle),
                            subject: Text("Join \(circle.name) on Pot Master"),
                            message: Text(CircleInviteSharing.message(for: circle))
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
                        guard let selectedCircleId, let circle = circleById[selectedCircleId] else { return }
                        selectedCurrencyCircle = circle
                    } label: {
                        HStack {
                            Label("Change currency", systemImage: "banknote")
                            Spacer()
                            if let selectedCircleId, let circle = circleById[selectedCircleId] {
                                Text("\(MoneyFormatting.currencySymbol(for: circle.currencyCode)) \(circle.currencyCode)")
                            }
                        }
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppTheme.card)
                        .foregroundStyle(selectedCircleId == nil ? AppTheme.muted : AppTheme.text)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.cardBorder))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCircleId == nil)
                }
                .padding()
                .background(AppTheme.background)
            }
            .onAppear {
                if selectedCircleId == nil {
                    selectedCircleId = orderedIds.first
                }
            }
        }
        .presentationBackground(AppTheme.background)
        .sheet(item: $selectedCurrencyCircle) { circle in
            CircleCurrencySettingsView(circle: circle)
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
        let repo = CircleRepository(context: context)
        for id in deletedIds {
            guard let circle = try? repo.fetch(id: id) else { continue }
            repo.delete(circle)
            if router.selectedCircleId == id {
                router.selectedCircleId = orderedIds.first
            }
        }
        CircleOrderStore.save(orderedIds)
        dismiss()
    }
}
