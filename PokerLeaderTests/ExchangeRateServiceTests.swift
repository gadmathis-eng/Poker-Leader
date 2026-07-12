import XCTest
@testable import PokerLeader

final class ExchangeRateServiceTests: XCTestCase {
    @MainActor
    func testConvertsBetweenNonBaseCurrencies() {
        let defaults = isolatedDefaults()
        let snapshot = ExchangeRateSnapshot(
            ratesPerBase: ["USD": 1, "GBP": 0.8, "ILS": 4],
            updatedAt: .now
        )
        ExchangeRateCache(defaults: defaults).save(snapshot)
        let service = ExchangeRateService(
            provider: StubExchangeRateProvider(snapshot: snapshot),
            cache: ExchangeRateCache(defaults: defaults)
        )

        XCTAssertEqual(service.convert(10, from: "GBP", to: "ILS"), 50)
    }

    @MainActor
    func testUsesCachedRatesWhenAvailable() {
        let defaults = isolatedDefaults()
        let cachedSnapshot = ExchangeRateSnapshot(
            ratesPerBase: ["USD": 1, "GBP": 0.5, "EUR": 2],
            updatedAt: .now
        )
        ExchangeRateCache(defaults: defaults).save(cachedSnapshot)

        let service = ExchangeRateService(
            provider: StubExchangeRateProvider(snapshot: ExchangeRateSnapshot(ratesPerBase: ["USD": 1], updatedAt: .now)),
            cache: ExchangeRateCache(defaults: defaults)
        )

        XCTAssertEqual(service.convert(10, from: "GBP", to: "EUR"), 40)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "ExchangeRateServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct StubExchangeRateProvider: ExchangeRateProvider {
    let snapshot: ExchangeRateSnapshot

    func fetchLatestRates() async throws -> ExchangeRateSnapshot {
        snapshot
    }
}
