import SwiftUI

struct PersonalSessionSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var sessionCurrencyCode: String
    @State private var buyInCurrencyCode: String
    @State private var buyInText: String
    @State private var currencyPickerTarget: CurrencyPickerTarget?
    @State private var editingBuyIn: MoneyAmountEditorState?

    let onSave: (String, String, Decimal) -> Void

    init(
        initialSessionCurrencyCode: String = CurrencyPreferences.defaultCurrencyCode,
        initialBuyInCurrencyCode: String = CurrencyPreferences.defaultCurrencyCode,
        initialBuyIn: Decimal = 0,
        onSave: @escaping (String, String, Decimal) -> Void
    ) {
        _sessionCurrencyCode = State(initialValue: initialSessionCurrencyCode)
        _buyInCurrencyCode = State(initialValue: initialBuyInCurrencyCode)
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
                Text("Set session currency and your buy-in")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                    .textCase(.uppercase)
            }
            .padding(.bottom, 24)

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
                        onSave(sessionCurrencyCode, buyInCurrencyCode, amount)
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

private enum CurrencyPickerTarget: Identifiable {
    case session
    case buyIn

    var id: Self { self }
}
