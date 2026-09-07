import SwiftUI

/// Asked before a guest sits: how much they want to put on the table.
struct JoinBuyInSheet: View {
    let hostName: String
    let currencyCode: String
    let initialAmount: Decimal
    let onConfirm: (Decimal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(
        hostName: String,
        currencyCode: String,
        initialAmount: Decimal = 0,
        onConfirm: @escaping (Decimal) -> Void
    ) {
        self.hostName = hostName
        self.currencyCode = currencyCode
        self.initialAmount = initialAmount
        self.onConfirm = onConfirm
        _text = State(
            initialValue: initialAmount > 0
                ? NSDecimalNumber(decimal: initialAmount).stringValue
                : "0"
        )
    }

    private var amount: Decimal {
        (Decimal(string: MoneyAmountKeypad.normalizedText(text)) ?? 0).clampedToNonNegative
    }

    private var canSit: Bool {
        amount > 0
    }

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(AppTheme.muted.opacity(0.4))
                .frame(width: 44, height: 4)

            VStack(spacing: 6) {
                Text("How much do you want to put in?")
                    .font(.headline)
                    .foregroundStyle(AppTheme.text)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
            }

            Text(MoneyFormatting.plain(amount, currencyCode: currencyCode))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.text)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .stroke(AppTheme.cardBorder)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .accessibilityLabel("Buy-in \(MoneyFormatting.plain(amount, currencyCode: currencyCode))")

            MoneyAmountKeypad(text: $text)

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
                    guard canSit else { return }
                    onConfirm(amount)
                    dismiss()
                } label: {
                    Text("Sit down")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canSit ? AppTheme.positive : AppTheme.card)
                        .foregroundStyle(canSit ? AppTheme.contrastText : AppTheme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                }
                .disabled(!canSit)
            }
        }
        .padding(20)
        .background(AppTheme.background)
    }

    private var subtitle: String {
        let trimmed = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || MemberModel.isPlaceholderName(trimmed) {
            return "Choose an amount, then pick a seat"
        }
        return "Before you sit at \(trimmed)'s table"
    }
}
