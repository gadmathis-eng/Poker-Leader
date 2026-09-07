import SwiftUI

struct EditOrderedListSheet<Item, Accessory: View, Footer: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let items: [Item]
    let id: KeyPath<Item, UUID>
    let code: (Item) -> String
    let name: (Item) -> String
    let subtitle: (Item) -> String
    let onSave: ([UUID], Set<UUID>) async -> Void
    let accessory: (Item?) -> Accessory
    let footer: (Item?) -> Footer

    @State private var orderedIds: [UUID]
    @State private var deletedIds: Set<UUID> = []
    @State private var selectedId: UUID?
    @State private var isSaving = false

    init(
        title: String,
        items: [Item],
        id: KeyPath<Item, UUID>,
        code: @escaping (Item) -> String,
        name: @escaping (Item) -> String,
        subtitle: @escaping (Item) -> String,
        onSave: @escaping ([UUID], Set<UUID>) async -> Void,
        @ViewBuilder accessory: @escaping (Item?) -> Accessory,
        @ViewBuilder footer: @escaping (Item?) -> Footer
    ) {
        self.title = title
        self.items = items
        self.id = id
        self.code = code
        self.name = name
        self.subtitle = subtitle
        self.onSave = onSave
        self.accessory = accessory
        self.footer = footer
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
                            HStack(spacing: 12) {
                                Text(code(item))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.muted)
                                    .frame(width: 36, alignment: .leading)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(name(item))
                                        .foregroundStyle(.primary)
                                    Text(subtitle(item))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.muted)
                                }
                                Spacer()
                                if selectedId == itemId {
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Group { accessory(selectedItem) }

                    Button {
                        Task { await save() }
                    } label: {
                        Text("Save")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppTheme.positive)
                            .foregroundStyle(AppTheme.contrastText)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)

                    Group { footer(selectedItem) }
                }
                .padding()
                .background(AppTheme.background)
            }
            .onAppear {
                if selectedId == nil {
                    selectedId = orderedIds.first
                }
            }
            .disabled(isSaving)
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
        let removed = Set(offsets.map { orderedIds[$0] })
        orderedIds.remove(atOffsets: offsets)
        if let selectedId, removed.contains(selectedId) {
            self.selectedId = orderedIds.first
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        await onSave(orderedIds, deletedIds)
        dismiss()
    }
}

struct EditOrderedListInviteCard: View {
    let code: String

    var body: some View {
        InviteCodeCopyLabel(code: code, style: .headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.cardBorder))
    }
}

struct EditOrderedListShareButton: View {
    let url: URL
    let subject: String
    let message: String
    var title: String = "Share invite"

    var body: some View {
        ShareLink(
            item: url,
            subject: Text(subject),
            message: Text(message)
        ) {
            Label(title, systemImage: "square.and.arrow.up")
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

struct EditOrderedListCurrencyButton: View {
    var currencyCode: String?
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label("Change currency", systemImage: "banknote")
                Spacer()
                if let currencyCode {
                    Text("\(MoneyFormatting.currencySymbol(for: currencyCode)) \(currencyCode)")
                }
            }
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding()
            .background(AppTheme.card)
            .foregroundStyle(isEnabled ? AppTheme.text : AppTheme.muted)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.cardBorder))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
