import Foundation

struct CurrencyPreference: Identifiable, Hashable {
    let countryCode: String
    let countryName: String
    let currencyCode: String
    let currencyName: String

    var id: String { currencyCode }
}

enum CurrencyPreferences {
    static let defaultCountryCode = "GB"
    static let defaultCurrencyCode = "GBP"

    static let featuredOptions: [CurrencyPreference] = [
        CurrencyPreference(countryCode: "US", countryName: "United States", currencyCode: "USD", currencyName: "US Dollar"),
        CurrencyPreference(countryCode: "GB", countryName: "United Kingdom", currencyCode: "GBP", currencyName: "British Pound"),
        CurrencyPreference(countryCode: "EU", countryName: "Europe", currencyCode: "EUR", currencyName: "Euro"),
        CurrencyPreference(countryCode: "IL", countryName: "Israel", currencyCode: "ILS", currencyName: "Israeli New Shekel"),
        CurrencyPreference(countryCode: "CA", countryName: "Canada", currencyCode: "CAD", currencyName: "Canadian Dollar"),
        CurrencyPreference(countryCode: "AU", countryName: "Australia", currencyCode: "AUD", currencyName: "Australian Dollar")
    ]

    static let options: [CurrencyPreference] = {
        let featuredCodes = Set(featuredOptions.map(\.currencyCode))
        let worldOptions = Locale.commonISOCurrencyCodes
            .map(normalizedCurrencyCode)
            .filter { !featuredCodes.contains($0) }
            .sorted()
            .map { code in
                CurrencyPreference(
                    countryCode: "",
                    countryName: "World currency",
                    currencyCode: code,
                    currencyName: Locale.current.localizedString(forCurrencyCode: code) ?? code
                )
            }

        return featuredOptions + worldOptions
    }()

    private static let validCurrencyCodes = Set(options.map(\.currencyCode))

    static func option(forCountryCode code: String) -> CurrencyPreference {
        options.first { $0.countryCode == code } ?? options.first { $0.countryCode == defaultCountryCode }!
    }

    static func option(forCurrencyCode code: String) -> CurrencyPreference {
        options.first { $0.currencyCode == code } ?? options.first { $0.currencyCode == defaultCurrencyCode }!
    }

    static func normalizedCurrencyCode(_ code: String) -> String {
        code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    static func isValidCurrencyCode(_ code: String) -> Bool {
        validCurrencyCodes.contains(normalizedCurrencyCode(code))
    }
}
