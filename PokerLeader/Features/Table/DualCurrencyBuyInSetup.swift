import SwiftUI

enum DualCurrencyPickerTarget: Identifiable {
    case session
    case buyIn

    var id: Self { self }
}

struct DualCurrencyBuyInSetup: View {
    @Binding var sessionCurrencyCode: String
    @Binding var buyInCurrencyCode: String
    @Binding var buyInText: String

    @State private var currencyPickerTarget: DualCurrencyPickerTarget?
    @State private var editingBuyIn: MoneyAmountEditorState?

    private var buyInAmount: Decimal? {
        Decimal(string: buyInText.trimmingCharacters(in: .whitespacesAndNewlines))?.clampedToNonNegative
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Session currency")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                Spacer()
                CurrencyChipButton(currencyCode: sessionCurrencyCode) {
                    currencyPickerTarget = .session
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
                currencyCode: buyInCurrencyCode,
                onAmountTap: {
                    editingBuyIn = MoneyAmountEditorState(
                        id: UUID(),
                        title: "My buy-in",
                        subtitle: "Personal amount",
                        currencyCode: buyInCurrencyCode,
                        text: buyInText
                    )
                },
                onCurrencyTap: {
                    currencyPickerTarget = .buyIn
                }
            )
        }
        .sheet(item: $editingBuyIn) { editor in
            MoneyAmountEditorSheet(editor: editor) { text in
                buyInText = text
            }
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $currencyPickerTarget) { target in
            CurrencyPickerSheet(
                selectedCurrencyCode: target == .session ? sessionCurrencyCode : buyInCurrencyCode
            ) { code in
                let cleaned = CurrencyPreferences.normalizedCurrencyCode(code)
                guard CurrencyPreferences.isValidCurrencyCode(cleaned) else { return }
                switch target {
                case .session:
                    sessionCurrencyCode = cleaned
                case .buyIn:
                    buyInCurrencyCode = cleaned
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
