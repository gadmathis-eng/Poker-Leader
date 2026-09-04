import SwiftUI

struct PersonalSessionSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var sessionCurrencyCode: String
    @State private var buyInCurrencyCode: String
    @State private var buyInText: String

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

            DualCurrencyBuyInSetup(
                sessionCurrencyCode: $sessionCurrencyCode,
                buyInCurrencyCode: $buyInCurrencyCode,
                buyInText: $buyInText
            )
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
    }
}
