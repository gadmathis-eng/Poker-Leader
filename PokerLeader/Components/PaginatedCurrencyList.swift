import SwiftUI

enum CurrencyListPagination {
    static let pageSize = 20
    static let prefetchThreshold = 5

    static func initialVisibleCount(in options: [CurrencyPreference], selectedCurrencyCode: String?) -> Int {
        guard
            let selectedCurrencyCode,
            let index = options.firstIndex(where: { $0.currencyCode == selectedCurrencyCode })
        else {
            return min(pageSize, options.count)
        }

        let needed = index + 1
        let roundedUp = ((needed + pageSize - 1) / pageSize) * pageSize
        return min(max(pageSize, roundedUp), options.count)
    }

    static func nextVisibleCount(current: Int, total: Int) -> Int {
        min(current + pageSize, total)
    }
}

struct PaginatedCurrencyList<Row: View>: View {
    let options: [CurrencyPreference]
    let selectedCurrencyCode: String?
    @ViewBuilder let row: (CurrencyPreference, Bool) -> Row

    @State private var visibleCount: Int

    init(
        options: [CurrencyPreference],
        selectedCurrencyCode: String? = nil,
        @ViewBuilder row: @escaping (CurrencyPreference, Bool) -> Row
    ) {
        self.options = options
        self.selectedCurrencyCode = selectedCurrencyCode
        self.row = row
        _visibleCount = State(
            initialValue: CurrencyListPagination.initialVisibleCount(
                in: options,
                selectedCurrencyCode: selectedCurrencyCode
            )
        )
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(visibleOptions) { option in
                row(option, option.id == visibleOptions.last?.id)
                    .onAppear {
                        loadMoreIfNeeded(for: option)
                    }
            }
        }
        .onChange(of: options.map(\.id)) { _, _ in
            resetVisibleCount()
        }
        .onChange(of: selectedCurrencyCode) { _, _ in
            resetVisibleCount()
        }
    }

    private var visibleOptions: [CurrencyPreference] {
        Array(options.prefix(visibleCount))
    }

    private func resetVisibleCount() {
        visibleCount = CurrencyListPagination.initialVisibleCount(
            in: options,
            selectedCurrencyCode: selectedCurrencyCode
        )
    }

    private func loadMoreIfNeeded(for option: CurrencyPreference) {
        guard let index = visibleOptions.firstIndex(where: { $0.id == option.id }) else { return }
        guard index >= visibleCount - CurrencyListPagination.prefetchThreshold else { return }
        guard visibleCount < options.count else { return }

        visibleCount = CurrencyListPagination.nextVisibleCount(
            current: visibleCount,
            total: options.count
        )
    }
}
