import Foundation

enum MoneyFormatting {
    static func format(_ amount: Decimal, currencyCode: String = "GBP") -> String {
        let symbol = currencyDisplayPrefix(for: currencyCode)
        let absValue = decimalString(abs(amount))

        if amount == 0 { return "\(symbol)0" }
        return amount >= 0 ? "+\(symbol)\(absValue)" : "-\(symbol)\(absValue)"
    }

    static func plain(_ amount: Decimal, currencyCode: String = "GBP") -> String {
        let symbol = currencyDisplayPrefix(for: currencyCode)
        return "\(symbol)\(decimalString(abs(amount)))"
    }

    static func decimalString(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = amountHasFraction(amount) ? 2 : 0

        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "0"
    }

    static func currencySymbol(for code: String) -> String {
        let normalizedCode = CurrencyPreferences.normalizedCurrencyCode(code)
        if let symbol = knownCurrencySymbols[normalizedCode] {
            return symbol
        }

        if let localizedSymbol = localizedCurrencySymbol(for: normalizedCode) {
            return localizedSymbol
        }

        return normalizedCode
    }

    private static func amountHasFraction(_ amount: Decimal) -> Bool {
        amount != Decimal(NSDecimalNumber(decimal: amount).intValue)
    }

    private static func currencyDisplayPrefix(for code: String) -> String {
        let symbol = currencySymbol(for: code)
        let normalizedCode = CurrencyPreferences.normalizedCurrencyCode(code)
        return symbol == normalizedCode ? "\(normalizedCode) " : symbol
    }

    private static func localizedCurrencySymbol(for code: String) -> String? {
        let identifiers = Locale.availableIdentifiers.filter { identifier in
            Locale(identifier: identifier).currency?.identifier == code
        }

        for identifier in identifiers {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = Locale(identifier: identifier)
            formatter.currencyCode = code

            if let symbol = formatter.currencySymbol?.cleanedCurrencySymbol,
               isUsableCurrencySymbol(symbol, for: code) {
                return symbol
            }
        }

        return nil
    }

    private static func isUsableCurrencySymbol(_ symbol: String, for code: String) -> Bool {
        !symbol.isEmpty && symbol != "¤" && symbol.localizedCaseInsensitiveCompare(code) != .orderedSame
    }

    private static let knownCurrencySymbols: [String: String] = [
        "AED": "د.إ",
        "AUD": "$",
        "BRL": "R$",
        "CAD": "$",
        "CHF": "CHF",
        "CNY": "¥",
        "DKK": "kr",
        "EUR": "€",
        "GBP": "£",
        "HKD": "$",
        "ILS": "₪",
        "INR": "₹",
        "JPY": "¥",
        "MXN": "$",
        "NOK": "kr",
        "NZD": "$",
        "PLN": "zł",
        "SEK": "kr",
        "SGD": "$",
        "USD": "$",
        "ZAR": "R"
    ]
}

private extension String {
    var cleanedCurrencySymbol: String {
        filter { !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
