import Foundation

enum TableCurrencyConversion {
    static func amountInTableCurrency(
        _ amount: Decimal,
        from sourceCurrencyCode: String,
        to tableCurrencyCode: String,
        using service: ExchangeRateService = .shared
    ) -> Decimal {
        service.convert(amount, from: sourceCurrencyCode, to: tableCurrencyCode)
            .roundedToHundredths
            .clampedToNonNegative
    }
}
