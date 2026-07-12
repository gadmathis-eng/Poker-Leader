import SwiftUI

struct CurrencyChipButton: View {
    let currencyCode: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(MoneyFormatting.currencySymbol(for: currencyCode))
                    .font(.caption.weight(.bold))
                Text(currencyCode)
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(AppTheme.text)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(AppTheme.background)
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(AppTheme.cardBorder)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }
}

struct CurrencyPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var allCurrenciesVisibleCount = CurrencyListPagination.pageSize

    let selectedCurrencyCode: String
    let onSelect: (String) -> Void

    private var filteredCurrencyOptions: [CurrencyPreference] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        return CurrencyPreferences.options.filter { option in
            option.currencyCode.localizedCaseInsensitiveContains(query) ||
            option.currencyName.localizedCaseInsensitiveContains(query) ||
            option.countryName.localizedCaseInsensitiveContains(query)
        }
    }

    private var listOptions: [CurrencyPreference] {
        searchText.isEmpty ? remainingOptions : filteredCurrencyOptions
    }

    private var visibleListOptions: [CurrencyPreference] {
        Array(listOptions.prefix(allCurrenciesVisibleCount))
    }

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    Section("Popular") {
                        ForEach(CurrencyPreferences.featuredOptions) { option in
                            currencyRow(option)
                        }
                    }
                }

                Section(searchText.isEmpty ? "All currencies" : "Results") {
                    ForEach(visibleListOptions) { option in
                        currencyRow(option)
                            .onAppear {
                                loadMoreCurrenciesIfNeeded(for: option)
                            }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Currency")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search currencies")
            .onChange(of: searchText) { _, _ in
                resetAllCurrenciesVisibleCount()
            }
            .onAppear {
                resetAllCurrenciesVisibleCount()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.muted)
                }
            }
        }
    }

    private var remainingOptions: [CurrencyPreference] {
        let featuredCodes = Set(CurrencyPreferences.featuredOptions.map(\.currencyCode))
        return CurrencyPreferences.options.filter { !featuredCodes.contains($0.currencyCode) }
    }

    private func resetAllCurrenciesVisibleCount() {
        allCurrenciesVisibleCount = CurrencyListPagination.initialVisibleCount(
            in: listOptions,
            selectedCurrencyCode: selectedCurrencyCode
        )
    }

    private func loadMoreCurrenciesIfNeeded(for option: CurrencyPreference) {
        guard let index = visibleListOptions.firstIndex(where: { $0.id == option.id }) else { return }
        guard index >= allCurrenciesVisibleCount - CurrencyListPagination.prefetchThreshold else { return }
        guard allCurrenciesVisibleCount < listOptions.count else { return }

        allCurrenciesVisibleCount = CurrencyListPagination.nextVisibleCount(
            current: allCurrenciesVisibleCount,
            total: listOptions.count
        )
    }

    private func currencyRow(_ option: CurrencyPreference) -> some View {
        Button {
            onSelect(option.currencyCode)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(MoneyFormatting.currencySymbol(for: option.currencyCode))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(option.currencyName)
                        .font(.body)
                        .foregroundStyle(AppTheme.text)
                    Text(option.currencyCode)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer(minLength: 0)

                if selectedCurrencyCode == option.currencyCode {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.positive)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
