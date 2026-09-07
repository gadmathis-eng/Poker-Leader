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
    let shareURL: URL
    let subject: String
    let message: String
    var shareTitle: String = "Share invite"

    var body: some View {
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

struct EditOrderedItemsSheet<Item, Row: View, Footer: View>: View {
    @Environment(\.dismiss) private var dismiss

    private let title: String
    private let items: [Item]
    private let id: KeyPath<Item, UUID>
    private let allowsSelection: Bool
    private let row: (Item, Bool) -> Row
    private let footer: (Item?) -> Footer
    private let onSave: ([UUID], Set<UUID>) -> Void

    @State private var orderedIds: [UUID]
    @State private var deletedIds: Set<UUID> = []
    @State private var selectedId: UUID?

    init(
        title: String,
        items: [Item],
        id: KeyPath<Item, UUID>,
        allowsSelection: Bool = true,
        onSave: @escaping (_ orderedIds: [UUID], _ deletedIds: Set<UUID>) -> Void,
        @ViewBuilder row: @escaping (Item, Bool) -> Row,
        @ViewBuilder footer: @escaping (Item?) -> Footer
    ) {
        self.title = title
        self.items = items
        self.id = id
        self.allowsSelection = allowsSelection
        self.row = row
        self.footer = footer
        self.onSave = onSave
        _orderedIds = State(initialValue: items.map { $0[keyPath: id] })
    }

    private var itemById: [UUID: Item] {
        Dictionary(uniqueKeysWithValues: items.map { ($0[keyPath: id], $0) })
    }

    private var selectedItem: Item? {
        selectedId.flatMap { itemById[$0] }
    }

    private var showsFooter: Bool {
        Footer.self != EmptyView.self
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(orderedIds, id: \.self) { itemId in
                    if let item = itemById[itemId] {
                        if allowsSelection {
                            Button {
                                selectedId = itemId
                            } label: {
                                row(item, selectedId == itemId)
                            }
                            .buttonStyle(.plain)
                        } else {
                            row(item, false)
                        }
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
            .safeAreaInset(edge: .bottom) {
                if showsFooter {
                    footer(selectedItem)
                        .padding()
                        .background(AppTheme.background)
                }
            }
            .onAppear {
                if allowsSelection, selectedId == nil {
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

extension EditOrderedItemsSheet where Footer == EmptyView {
    init(
        title: String,
        items: [Item],
        id: KeyPath<Item, UUID>,
        onSave: @escaping (_ orderedIds: [UUID], _ deletedIds: Set<UUID>) -> Void,
        @ViewBuilder row: @escaping (Item, Bool) -> Row
    ) {
        self.init(
            title: title,
            items: items,
            id: id,
            allowsSelection: false,
            onSave: onSave,
            row: row,
            footer: { _ in EmptyView() }
        )
    }
}
