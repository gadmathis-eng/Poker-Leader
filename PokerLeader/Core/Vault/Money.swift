import Foundation

/// An amount of money as a whole number of the currency's minor unit — cents,
/// pence, agorot. Nothing in the Vault is ever a `Double`: a balance that can be
/// added, split and settled thousands of times cannot afford rounding drift, and
/// the backend stores the same integer.
///
/// `Decimal` is still the currency of the rest of the app, so `init(decimal:)`
/// and `decimalValue` are the two crossings between them, and both round to the
/// nearest cent rather than truncating.
struct Money: Hashable, Comparable, Codable, Sendable {
    let cents: Int

    init(cents: Int) {
        self.cents = cents
    }

    init(decimal: Decimal) {
        var scaled = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        self.cents = NSDecimalNumber(decimal: rounded).intValue
    }

    static let zero = Money(cents: 0)

    var decimalValue: Decimal {
        Decimal(cents) / 100
    }

    var isZero: Bool { cents == 0 }
    var isPositive: Bool { cents > 0 }
    var isNegative: Bool { cents < 0 }
    var magnitude: Money { Money(cents: abs(cents)) }

    static func < (lhs: Money, rhs: Money) -> Bool { lhs.cents < rhs.cents }
    static func + (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents + rhs.cents) }
    static func - (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents - rhs.cents) }
    static prefix func - (value: Money) -> Money { Money(cents: -value.cents) }

    func clampedToNonNegative() -> Money {
        Money(cents: max(cents, 0))
    }

    func formatted(currencyCode: String) -> String {
        MoneyFormatting.plain(decimalValue, currencyCode: currencyCode)
    }

    /// Leading `+` or `-`, for a statement where the direction matters.
    func formattedSigned(currencyCode: String) -> String {
        MoneyFormatting.format(decimalValue, currencyCode: currencyCode)
    }

    init(from decoder: Decoder) throws {
        cents = try decoder.singleValueContainer().decode(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(cents)
    }
}

extension Money {
    /// Parses what someone typed into a keypad. Anything that is not a digit or
    /// a separator is dropped, and more than two decimal places is rounded.
    init?(userInput: String, locale: Locale = .current) {
        let separator = locale.decimalSeparator ?? "."
        let cleaned = userInput
            .replacingOccurrences(of: separator, with: ".")
            .filter { $0.isNumber || $0 == "." }

        guard !cleaned.isEmpty, let value = Decimal(string: cleaned) else { return nil }
        self.init(decimal: value)
    }
}
