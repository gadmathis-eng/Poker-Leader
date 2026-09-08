import Foundation

/// Server-side exchange rates used when Vault money crosses a currency.
///
/// The wallet is one pot. A table or a cash-out can be another currency, so
/// the cents that leave the wallet are not the cents that land on the table or
/// on the payout. This is the same table the Postgres functions use
/// (`vault_fx_rates` / `HardcodedExchangeRateProvider`), so a demo device and
/// the real backend convert any published pair the same way.
enum VaultFX {
    static let ratesPerUSD: [String: Decimal] = HardcodedExchangeRateProvider.ratesPerUSD

    static var supportedCurrencyCodes: Set<String> {
        Set(ratesPerUSD.keys)
    }

    static func normalize(_ code: String) -> String {
        CurrencyPreferences.normalizedCurrencyCode(code)
    }

    static func supports(_ currencyCode: String) -> Bool {
        ratePerUSD(for: currencyCode) != nil
    }

    /// Currency the Vault opens in when the player has no wallet yet: their
    /// preferred unit, if we publish a rate for it.
    static func preferredOpeningCurrency() -> String {
        let stored = UserDefaults.standard.string(forKey: "preferredCurrencyCode")
            ?? CurrencyPreferences.defaultCurrencyCode
        let code = normalize(stored)
        if supports(code) { return code }
        if supports(CurrencyPreferences.defaultCurrencyCode) {
            return CurrencyPreferences.defaultCurrencyCode
        }
        return "USD"
    }

    static func ratePerUSD(for currencyCode: String) -> Decimal? {
        let code = normalize(currencyCode)
        if code == "USD" { return 1 }
        return ratesPerUSD[code]
    }

    /// Whole cents of `to` for whole cents of `from`, rounded half away from
    /// zero so it matches `round()` in Postgres.
    static func convert(cents: Int, from sourceCurrencyCode: String, to targetCurrencyCode: String) -> Int? {
        let source = normalize(sourceCurrencyCode)
        let target = normalize(targetCurrencyCode)
        guard source != target else { return cents }
        guard
            let sourceRate = ratePerUSD(for: source),
            let targetRate = ratePerUSD(for: target),
            sourceRate != 0
        else {
            return nil
        }

        var result = Decimal(cents) * targetRate / sourceRate
        var rounded = Decimal()
        NSDecimalRound(&rounded, &result, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    static func convert(_ money: Money, from sourceCurrencyCode: String, to targetCurrencyCode: String) -> Money? {
        guard let cents = convert(cents: money.cents, from: sourceCurrencyCode, to: targetCurrencyCode) else {
            return nil
        }
        return Money(cents: cents)
    }

    static func convertRequired(cents: Int, from sourceCurrencyCode: String, to targetCurrencyCode: String) throws -> Int {
        guard let cents = convert(cents: cents, from: sourceCurrencyCode, to: targetCurrencyCode) else {
            throw VaultError.backend(
                "No exchange rate between \(normalize(sourceCurrencyCode)) and \(normalize(targetCurrencyCode))."
            )
        }
        return cents
    }
}
