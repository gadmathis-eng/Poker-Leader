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
        "UAH": 40.5
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
