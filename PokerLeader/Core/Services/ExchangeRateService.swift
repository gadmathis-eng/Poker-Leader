import Foundation

struct ExchangeRateSnapshot: Codable, Equatable {
    let baseCurrencyCode: String
    let ratesPerBase: [String: String]
    let updatedAt: Date

    init(baseCurrencyCode: String = "USD", ratesPerBase: [String: Decimal], updatedAt: Date) {
        self.baseCurrencyCode = CurrencyPreferences.normalizedCurrencyCode(baseCurrencyCode)
        self.ratesPerBase = Dictionary(
            uniqueKeysWithValues: ratesPerBase.map { code, rate in
                (CurrencyPreferences.normalizedCurrencyCode(code), NSDecimalNumber(decimal: rate).stringValue)
            }
        )
        self.updatedAt = updatedAt
    }

    func ratePerBase(for currencyCode: String) -> Decimal? {
        let code = CurrencyPreferences.normalizedCurrencyCode(currencyCode)
        if code == baseCurrencyCode {
            return 1
        }
        return ratesPerBase[code].flatMap { Decimal(string: $0) }
    }
}

protocol ExchangeRateProvider {
    func fetchLatestRates() async throws -> ExchangeRateSnapshot
}

struct HardcodedExchangeRateProvider: ExchangeRateProvider {
    func fetchLatestRates() async throws -> ExchangeRateSnapshot {
        ExchangeRateSnapshot(ratesPerBase: Self.ratesPerUSD, updatedAt: .now)
    }

    static let ratesPerUSD: [String: Decimal] = [
        "USD": 1,
        "GBP": 0.79,
        "EUR": 0.92,
        "ILS": 3.72,
        "CAD": 1.36,
        "AUD": 1.51,
        "JPY": 157.0,
        "CHF": 0.89,
        "CNY": 7.24,
        "HKD": 7.81,
        "SGD": 1.35,
        "NZD": 1.64,
        "SEK": 10.5,
        "NOK": 10.7,
        "DKK": 6.86,
        "PLN": 3.99,
        "CZK": 22.9,
        "HUF": 360.0,
        "RON": 4.58,
        "BGN": 1.80,
        "TRY": 32.6,
        "MXN": 18.0,
        "BRL": 5.42,
        "ARS": 905.0,
        "CLP": 940.0,
        "COP": 4100.0,
        "PEN": 3.75,
        "ZAR": 18.2,
        "INR": 83.5,
        "KRW": 1380.0,
        "THB": 36.7,
        "MYR": 4.71,
        "IDR": 16200.0,
        "PHP": 58.5,
        "VND": 25400.0,
        "AED": 3.67,
        "SAR": 3.75,
        "QAR": 3.64,
        "KWD": 0.31,
        "BHD": 0.38,
        "OMR": 0.38,
        "EGP": 48.0,
        "MAD": 9.95,
        "NGN": 1500.0,
        "KES": 129.0,
        "GHS": 15.0,
        "RUB": 89.0,
        "UAH": 40.5,
        "TWD": 32.5,
        "PKR": 278.0,
        "BDT": 110.0,
        "LKR": 300.0,
        "NPR": 133.0,
        "MMK": 2100.0,
        "KHR": 4100.0,
        "LAK": 21600.0,
        "MNT": 3450.0,
        "KZT": 450.0,
        "UZS": 12700.0,
        "GEL": 2.70,
        "AMD": 390.0,
        "AZN": 1.70,
        "BYN": 3.27,
        "MDL": 17.8,
        "MKD": 56.5,
        "ALL": 92.0,
        "BAM": 1.80,
        "RSD": 108.0,
        "ISK": 138.0,
        "MOP": 8.03,
        "TND": 3.12,
        "DZD": 134.0,
        "LBP": 89500.0,
        "JOD": 0.71,
        "IQD": 1310.0,
        "IRR": 42000.0,
        "AFN": 71.0,
        "CRC": 515.0,
        "UYU": 40.0,
        "BOB": 6.91,
        "PYG": 7500.0,
        "GTQ": 7.75,
        "HNL": 24.7,
        "NIO": 36.6,
        "DOP": 59.0,
        "JMD": 156.0,
        "TTD": 6.78,
        "BZD": 2.02,
        "XCD": 2.70,
        "BBD": 2.00,
        "BSD": 1,
        "KYD": 0.83,
        "BMD": 1,
        "FJD": 2.25,
        "PGK": 3.90,
        "WST": 2.75,
        "TOP": 2.35,
        "VUV": 119.0,
        "XPF": 110.0,
        "XOF": 605.0,
        "XAF": 605.0,
        "MUR": 46.0,
        "NAD": 18.2,
        "BWP": 13.6,
        "ZMW": 26.0,
        "UGX": 3750.0,
        "TZS": 2650.0,
        "ETB": 57.0,
        "RWF": 1300.0,
        "MGA": 4500.0,
        "AOA": 850.0,
        "MZN": 64.0,
        "CVE": 102.0,
        "GMD": 68.0,
        "SLL": 22500.0,
        "LRD": 195.0,
        "MWK": 1730.0,
        "SZL": 18.2,
        "LSL": 18.2,
        "MRU": 39.8,
        "KMF": 450.0,
        "STN": 22.6,
        "DJF": 178.0,
        "SOS": 570.0,
        "SDG": 600.0,
        "SSP": 1500.0,
        "LYD": 4.82,
        "SYP": 13000.0,
        "YER": 250.0,
        "BND": 1.35,
        "PAB": 1,
        "ANG": 1.80,
        "AWG": 1.80,
        "SRD": 32.0,
        "GYD": 209.0,
        "HTG": 132.0,
        "CUP": 24.0,
        "VES": 36.5,
        "BTN": 83.5,
        "MVR": 15.4,
        "SCR": 13.6,
        "KGS": 87.0,
        "TJS": 10.9,
        "TMT": 3.50,
        "SBD": 8.45,
        "FKP": 0.79,
        "GIP": 0.79,
        "SHP": 0.79,
        "JEP": 0.79,
        "GGP": 0.79,
        "IMP": 0.79,
        "CDF": 2850.0,
        "GNF": 8600.0,
        "BIF": 2900.0,
        "ERN": 15.0,
        "SLE": 22.5
    ]
}

struct ExchangeRateCache {
    private let defaults: UserDefaults
    private let key = "cachedExchangeRates"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ExchangeRateSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ExchangeRateSnapshot.self, from: data)
    }

    func save(_ snapshot: ExchangeRateSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}

final class ExchangeRateService {
    static let shared = ExchangeRateService()

    private let provider: ExchangeRateProvider
    private let cache: ExchangeRateCache
    private(set) var snapshot: ExchangeRateSnapshot

    private let refreshInterval: TimeInterval = 24 * 60 * 60

    init(
        provider: ExchangeRateProvider = HardcodedExchangeRateProvider(),
        cache: ExchangeRateCache = ExchangeRateCache()
    ) {
        self.provider = provider
        self.cache = cache
        self.snapshot = cache.load() ?? ExchangeRateSnapshot(ratesPerBase: HardcodedExchangeRateProvider.ratesPerUSD, updatedAt: .now)
        cache.save(snapshot)
    }

    func refreshIfNeeded(now: Date = .now) async {
        guard now.timeIntervalSince(snapshot.updatedAt) >= refreshInterval else { return }

        do {
            let latest = try await provider.fetchLatestRates()
            snapshot = latest
            cache.save(latest)
        } catch {
            // Keep using the most recent cached rates. A live provider can fail offline without blocking the app.
        }
    }

    func convert(_ amount: Decimal, from sourceCurrencyCode: String, to targetCurrencyCode: String) -> Decimal {
        let sourceCode = CurrencyPreferences.normalizedCurrencyCode(sourceCurrencyCode)
        let targetCode = CurrencyPreferences.normalizedCurrencyCode(targetCurrencyCode)
        guard sourceCode != targetCode else { return amount }

        guard
            let sourceRate = snapshot.ratePerBase(for: sourceCode),
            let targetRate = snapshot.ratePerBase(for: targetCode),
            sourceRate != 0
        else {
            return amount
        }

        return amount / sourceRate * targetRate
    }

    var rateStatusText: String {
        let days = max(0, Calendar.current.dateComponents([.day], from: snapshot.updatedAt, to: .now).day ?? 0)
        switch days {
        case 0:
            return "Rates updated today."
        case 1:
            return "Rates updated yesterday."
        default:
            return "Rates updated \(days) days ago."
        }
    }
}
