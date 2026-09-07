import SwiftUI

/// Compact editable ante: the label on the left, a currency chip with a pencil on the right.
struct AnteEditorRow: View {
    let amount: Decimal
    let currencyCode: String
    var isEditable: Bool = true
    let action: () -> Void

    private var currencySymbol: String {
        MoneyFormatting.currencySymbol(for: currencyCode)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text("Ante")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.text)

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Text(currencySymbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                    Text(MoneyFormatting.decimalString(amount))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.gold)
                        .monospacedDigit()
                    if isEditable {
                        Image(systemName: "pencil")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
        .accessibilityLabel(isEditable ? "Edit ante" : "Ante")
        .accessibilityValue(MoneyFormatting.plain(amount, currencyCode: currencyCode))
    }
}
