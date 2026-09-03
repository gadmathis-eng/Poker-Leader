import SwiftUI

struct PersonalSessionSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var currencyCode: String
    @State private var buyInText: String
    @State private var showingCurrencyPicker = false
    @State private var editingBuyIn: MoneyAmountEditorState?

    let onSave: (String, Decimal) -> Void

    init(
        initialCurrencyCode: String = CurrencyPreferences.defaultCurrencyCode,
        initialBuyIn: Decimal = 0,
        onSave: @escaping (String, Decimal) -> Void
    ) {
        _currencyCode = State(initialValue: initialCurrencyCode)
        _buyInText = State(initialValue: initialBuyIn > 0 ? NSDecimalNumber(decimal: initialBuyIn).stringValue : "0")
        self.onSave = onSave
    }

    private var buyInAmount: Decimal? {
        Decimal(string: buyInText.trimmingCharacters(in: .whitespacesAndNewlines))?.clampedToNonNegative
    }

    private var canSave: Bool {
        (buyInAmount ?? 0) > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(AppTheme.muted.opacity(0.4))
                .frame(width: 44, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            VStack(spacing: 6) {
                Text("New session")
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.text)
                Text("Set your personal buy-in")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                    .textCase(.uppercase)
            }
            .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Currency")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                    Spacer()
                    CurrencyChipButton(currencyCode: currencyCode) {
                        showingCurrencyPicker = true
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .stroke(AppTheme.cardBorder)
                )

                StandardBuyInCard(
                    amount: buyInAmount ?? 0,
                    currencyCode: currencyCode,
                    onAmountTap: {
                        editingBuyIn = MoneyAmountEditorState(
                            id: UUID(),
                            title: "My buy-in",
                            subtitle: "Personal amount",
                            currencyCode: currencyCode,
                            text: buyInText
                        )
                    },
                    onCurrencyTap: {
                        showingCurrencyPicker = true
                    }
                )
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 24)

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppTheme.card)
                .foregroundStyle(AppTheme.text)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

                Button {
                    if let amount = buyInAmount {
                        onSave(currencyCode, amount)
                        dismiss()
                    }
                } label: {
                    Text("Save buy-in")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canSave ? AppTheme.positive : AppTheme.card)
                        .foregroundStyle(canSave ? AppTheme.contrastText : AppTheme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                }
                .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(AppTheme.background)
        .sheet(item: $editingBuyIn) { editor in
            MoneyAmountEditorSheet(editor: editor) { text in
                buyInText = text
            }
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingCurrencyPicker) {
            CurrencyPickerSheet(selectedCurrencyCode: currencyCode) { code in
                let cleaned = CurrencyPreferences.normalizedCurrencyCode(code)
                if CurrencyPreferences.isValidCurrencyCode(cleaned) {
                    currencyCode = cleaned
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
