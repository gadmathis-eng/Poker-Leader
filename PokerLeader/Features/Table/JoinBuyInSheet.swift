import SwiftUI

/// Asked before a guest sits: how much they want to put on the table, and in
/// which currency. A different currency is converted into the table's money.
struct JoinBuyInSheet: View {
    let hostName: String
    let tableCurrencyCode: String
    let initialPayInCurrencyCode: String
    let initialAmount: Decimal
    let onConfirm: (Decimal, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var payInCurrencyCode: String
    @State private var showCurrencyPicker = false

    init(
        hostName: String,
        tableCurrencyCode: String,
        initialPayInCurrencyCode: String,
        initialAmount: Decimal = 0,
        onConfirm: @escaping (Decimal, String) -> Void
    ) {
        self.hostName = hostName
        self.tableCurrencyCode = tableCurrencyCode
        self.initialPayInCurrencyCode = initialPayInCurrencyCode
        self.initialAmount = initialAmount
        self.onConfirm = onConfirm
        let payIn = CurrencyPreferences.isValidCurrencyCode(initialPayInCurrencyCode)
            ? CurrencyPreferences.normalizedCurrencyCode(initialPayInCurrencyCode)
            : tableCurrencyCode
        _payInCurrencyCode = State(initialValue: payIn)
        _text = State(
            initialValue: initialAmount > 0
                ? NSDecimalNumber(decimal: initialAmount).stringValue
                : "0"
        )
    }

    private var amount: Decimal {
        (Decimal(string: MoneyAmountKeypad.normalizedText(text)) ?? 0).clampedToNonNegative
    }

    private var tableAmount: Decimal {
        TableCurrencyConversion.amountInTableCurrency(
            amount,
            from: payInCurrencyCode,
            to: tableCurrencyCode
        )
    }

    private var showsConversion: Bool {
        payInCurrencyCode != tableCurrencyCode && amount > 0
    }

    private var canSit: Bool {
        amount > 0
    }

    var body: some View {
        VStack(spacing: 16) {
            SheetDragHandle()

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

            VStack(spacing: 8) {
                HStack {
                    Text("You put in")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                    Spacer()
                    CurrencyChipButton(currencyCode: payInCurrencyCode) {
                        showCurrencyPicker = true
                    }
                    .accessibilityLabel("Choose currency")
                }

                Text(MoneyFormatting.plain(amount, currencyCode: payInCurrencyCode))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.text)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Buy-in \(MoneyFormatting.plain(amount, currencyCode: payInCurrencyCode))")

                if showsConversion {
                    Text("That's \(MoneyFormatting.plain(tableAmount, currencyCode: tableCurrencyCode)) on the table.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .background(AppTheme.card)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.cardBorder)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

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
                    onConfirm(amount, payInCurrencyCode)
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
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showCurrencyPicker) {
            CurrencyPickerSheet(selectedCurrencyCode: payInCurrencyCode) { code in
                let cleaned = CurrencyPreferences.normalizedCurrencyCode(code)
                guard CurrencyPreferences.isValidCurrencyCode(cleaned) else { return }
                payInCurrencyCode = cleaned
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var subtitle: String {
        let trimmed = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || MemberModel.isPlaceholderName(trimmed) {
            return "Choose an amount and currency, then pick a seat"
        }
        return "Before you sit at \(trimmed)'s table"
    }
}
