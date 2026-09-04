import Foundation
import SwiftUI

struct MoneyAmountEditorState: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    let currencyCode: String
    var text: String
    var maximum: Decimal? = nil
}

struct MoneyAmountPill: View {
    let label: String
    let amount: Decimal
    let currencyCode: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
            Text(MoneyFormatting.plain(amount, currencyCode: currencyCode))
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(AppTheme.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.background.opacity(0.75))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.cardBorder)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct StandardBuyInCard: View {
    let amount: Decimal
    let currencyCode: String
    let onAmountTap: () -> Void
    let onCurrencyTap: () -> Void

    private var currencySymbol: String {
        MoneyFormatting.currencySymbol(for: currencyCode)
    }

    private var normalizedCurrencyCode: String {
        CurrencyPreferences.normalizedCurrencyCode(currencyCode)
    }

    private var usesCompactSymbolLayout: Bool {
        currencySymbol != normalizedCurrencyCode && !currencySymbol.contains(" ")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("Buy-in")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                Spacer()
                CurrencyChipButton(currencyCode: currencyCode, action: onCurrencyTap)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Button(action: onAmountTap) {
                Group {
                    if usesCompactSymbolLayout {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text(currencySymbol)
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.muted)
                                .offset(y: -4)
                            Text(MoneyFormatting.decimalString(amount))
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.text)
                                .monospacedDigit()
                        }
                    } else {
                        Text(MoneyFormatting.plain(amount, currencyCode: currencyCode))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.text)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background {
                    AppTheme.background
                        .clipShape(
                            UnevenRoundedRectangle(
                                cornerRadii: .init(
                                    bottomLeading: AppTheme.cornerRadius,
                                    bottomTrailing: AppTheme.cornerRadius
                                )
                            )
                        )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(BuyInAmountButtonStyle())
        }
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.cardBorder)
        )
    }
}

private struct BuyInAmountButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct MoneyAmountEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    let title: String
    let subtitle: String
    let currencyCode: String
    let maximum: Decimal?
    let onSave: (String) -> Void

    init(editor: MoneyAmountEditorState, onSave: @escaping (String) -> Void) {
        self.title = editor.title
        self.subtitle = editor.subtitle
        self.currencyCode = editor.currencyCode
        self.maximum = editor.maximum
        self.onSave = onSave
        _text = State(initialValue: editor.text)
    }

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(AppTheme.muted.opacity(0.4))
                .frame(width: 44, height: 4)

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.text)
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                    .textCase(.uppercase)
            }

            Group {
                if usesCompactSymbolLayout {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(currencySymbol)
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.muted)
                            .offset(y: -4)
                        Text(MoneyFormatting.decimalString(currentAmount))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.text)
                            .monospacedDigit()
                    }
                } else {
                    Text(displayAmount)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.text)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.card)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.cardBorder)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

            MoneyAmountKeypad(text: $text, maximum: maximum)

            HStack(spacing: 12) {
                Button("Clear") {
                    text = "0"
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppTheme.card)
                .foregroundStyle(AppTheme.text)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

                Button(action: commitAmount) {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canSave ? AppTheme.positive : AppTheme.card)
                        .foregroundStyle(canSave ? AppTheme.contrastText : AppTheme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                }
                .disabled(!canSave)
                .accessibilityLabel("Set")
            }
        }
        .padding(20)
        .background(AppTheme.background)
    }

    private var canSave: Bool {
        Decimal(string: MoneyAmountKeypad.normalizedText(text)) != nil
    }

    private var currentAmount: Decimal {
        (Decimal(string: MoneyAmountKeypad.normalizedText(text)) ?? 0).clampedToNonNegative
    }

    private var displayAmount: String {
        MoneyFormatting.plain(currentAmount, currencyCode: currencyCode)
    }

    private var currencySymbol: String {
        MoneyFormatting.currencySymbol(for: currencyCode)
    }

    private var usesCompactSymbolLayout: Bool {
        let code = CurrencyPreferences.normalizedCurrencyCode(currencyCode)
        return currencySymbol != code && !currencySymbol.contains(" ")
    }

    private func commitAmount() {
        let value = MoneyAmountKeypad.committedText(text, maximum: maximum)
        guard Decimal(string: value) != nil else { return }
        onSave(value)
        dismiss()
    }
}

struct MoneyAmountKeypad: View {
    @Binding var text: String
    var maximum: Decimal? = nil

    var body: some View {
        VStack(spacing: 8) {
            keypadRow(["1", "2", "3"])
            keypadRow(["4", "5", "6"])
            keypadRow(["7", "8", "9"])
            HStack(spacing: 8) {
                keypadButton(".")
                keypadButton("0")
                deleteKey
            }
        }
    }

    static func normalizedText(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix(".") {
            value.removeLast()
        }
        return value.isEmpty ? "0" : value
    }

    static func committedText(_ text: String, maximum: Decimal?) -> String {
        var value = normalizedText(text)
        if let maximum, let typed = Decimal(string: value), typed > maximum {
            value = NSDecimalNumber(decimal: maximum).stringValue
        }
        return value
    }

    private var deleteKey: some View {
        Button(action: deleteLast) {
            Image(systemName: "delete.left")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(KeypadButtonStyle())
        .accessibilityLabel("Delete")
    }

    private func keypadRow(_ values: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(values, id: \.self, content: keypadButton)
        }
    }

    private func keypadButton(_ value: String) -> some View {
        Button(value) {
            append(value)
        }
        .buttonStyle(KeypadButtonStyle())
    }

    private func append(_ value: String) {
        if value == ".", text.contains(".") { return }

        var next = text
        if next == "0", value != "." {
            next = value
        } else {
            next.append(value)
        }

        if let separator = next.firstIndex(of: ".") {
            let fraction = next[next.index(after: separator)...]
            if fraction.count > 2 { return }
        }

        if let typed = Decimal(string: next) {
            if let maximum, typed > maximum {
                text = NSDecimalNumber(decimal: maximum).stringValue
                return
            }
            if typed < 0 {
                return
            }
        }

        text = next
    }

    private func deleteLast() {
        guard !text.isEmpty else { return }
        text.removeLast()
        if text.isEmpty {
            text = "0"
        }
    }
}

private struct KeypadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.title3, design: .rounded).weight(.bold))
            .foregroundStyle(AppTheme.text)
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? AppTheme.positive.opacity(0.35) : AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
