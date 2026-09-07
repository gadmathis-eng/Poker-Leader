import SwiftUI

struct EditOrderedItemRow: View {
    let leadingText: String
    let title: String
    let subtitle: String

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
        }
    }
}

struct EditOrderedItemsSheet<Item, Row: View>: View {
    @Environment(\.dismiss) private var dismiss

    private let title: String
    private let items: [Item]
    private let id: KeyPath<Item, UUID>
    private let row: (Item) -> Row
    private let onSave: ([UUID], Set<UUID>) -> Void

    @State private var orderedIds: [UUID]
    @State private var deletedIds: Set<UUID> = []

    init(
        title: String,
        items: [Item],
        id: KeyPath<Item, UUID>,
        onSave: @escaping (_ orderedIds: [UUID], _ deletedIds: Set<UUID>) -> Void,
        @ViewBuilder row: @escaping (Item) -> Row
    ) {
        self.title = title
        self.items = items
        self.id = id
        self.row = row
        self.onSave = onSave
        _orderedIds = State(initialValue: items.map { $0[keyPath: id] })
    }

    private var itemById: [UUID: Item] {
        Dictionary(uniqueKeysWithValues: items.map { ($0[keyPath: id], $0) })
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(orderedIds, id: \.self) { itemId in
                    if let item = itemById[itemId] {
                        row(item)
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
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
    }

    private func save() {
        onSave(orderedIds, deletedIds)
        dismiss()
    }
}
