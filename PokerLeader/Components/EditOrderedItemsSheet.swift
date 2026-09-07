import SwiftUI

struct EditOrderedItemRow: View {
    let leadingText: String
    let title: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(leadingText)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.muted)
                .frame(minWidth: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.positive)
            }
        }
    }
}

struct EditOrderedItemInviteActions: View {
    let code: String
    let shareURL: URL
    let subject: String
    let message: String
    var shareTitle: String = "Share invite"

    var body: some View {
        VStack(spacing: 12) {
            InviteCodeCopyLabel(code: code, style: .headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.cardBorder))

            ShareLink(
                item: shareURL,
                subject: Text(subject),
                message: Text(message)
            ) {
                Label(shareTitle, systemImage: "square.and.arrow.up")
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
    }
}

struct EditOrderedItemsSheet<Item, Row: View, AboveSave: View, BelowSave: View>: View {
    @Environment(\.dismiss) private var dismiss

    private let title: String
    private let items: [Item]
    private let id: KeyPath<Item, UUID>
    private let row: (Item, Bool) -> Row
    private let aboveSave: (Item?) -> AboveSave
    private let belowSave: (Item?) -> BelowSave
    private let onSave: ([UUID], Set<UUID>) -> Void

    @State private var orderedIds: [UUID]
    @State private var deletedIds: Set<UUID> = []
    @State private var selectedId: UUID?

    init(
        title: String,
        items: [Item],
        id: KeyPath<Item, UUID>,
        onSave: @escaping (_ orderedIds: [UUID], _ deletedIds: Set<UUID>) -> Void,
        @ViewBuilder row: @escaping (Item, Bool) -> Row,
        @ViewBuilder aboveSave: @escaping (Item?) -> AboveSave,
        @ViewBuilder belowSave: @escaping (Item?) -> BelowSave
    ) {
        self.title = title
        self.items = items
        self.id = id
        self.row = row
        self.aboveSave = aboveSave
        self.belowSave = belowSave
        self.onSave = onSave
        _orderedIds = State(initialValue: items.map { $0[keyPath: id] })
    }

    private var itemById: [UUID: Item] {
        Dictionary(uniqueKeysWithValues: items.map { ($0[keyPath: id], $0) })
    }

    private var selectedItem: Item? {
        selectedId.flatMap { itemById[$0] }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(orderedIds, id: \.self) { itemId in
                    if let item = itemById[itemId] {
                        Button {
                            selectedId = itemId
                        } label: {
                            row(item, selectedId == itemId)
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    aboveSave(selectedItem)

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

                    belowSave(selectedItem)
                }
                .padding()
                .background(AppTheme.background)
            }
            .onAppear {
                if selectedId == nil {
                    selectedId = orderedIds.first
                }
            }
        }
        .presentationBackground(AppTheme.background)
    }

    private func move(from source: IndexSet, to destination: Int) {
        orderedIds.move(fromOffsets: source, toOffset: destination)
    }

    private func remove(at offsets: IndexSet) {
        for index in offsets {
            deletedIds.insert(orderedIds[index])
        }
        orderedIds.remove(atOffsets: offsets)
        if let selectedId, !orderedIds.contains(selectedId) {
            self.selectedId = orderedIds.first
        }
    }

    private func save() {
        onSave(orderedIds, deletedIds)
        dismiss()
    }
}
