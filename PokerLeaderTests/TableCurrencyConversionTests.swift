import XCTest
@testable import PokerLeader

final class TableCurrencyConversionTests: XCTestCase {
    func testKeepsAmountWhenCurrenciesMatch() {
        let service = makeService(rates: ["USD": 1, "GBP": 0.8])

        XCTAssertEqual(
            TableCurrencyConversion.amountInTableCurrency(
                20,
                from: "GBP",
                to: "GBP",
                using: service
            ),
            20
        )
    }

    func testConvertsPersonalBuyInIntoTableCurrency() {
        let service = makeService(rates: ["USD": 1, "GBP": 0.8])

        XCTAssertEqual(
            TableCurrencyConversion.amountInTableCurrency(
                20,
                from: "GBP",
                to: "USD",
                using: service
            ),
            25
        )
    }

    func testRoundsConvertedAmountToHundredths() {
        let service = makeService(rates: ["USD": 1, "GBP": 0.79])

        XCTAssertEqual(
            TableCurrencyConversion.amountInTableCurrency(
                20,
                from: "GBP",
                to: "USD",
                using: service
            ),
            Decimal(string: "25.32")
        )
    }

    private func makeService(rates: [String: Decimal]) -> ExchangeRateService {
        let suiteName = "TableCurrencyConversionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let snapshot = ExchangeRateSnapshot(ratesPerBase: rates, updatedAt: .now)
        ExchangeRateCache(defaults: defaults).save(snapshot)
        return ExchangeRateService(
            provider: StubTableRateProvider(snapshot: snapshot),
            cache: ExchangeRateCache(defaults: defaults)
        )
    }
}

private struct StubTableRateProvider: ExchangeRateProvider {
    let snapshot: ExchangeRateSnapshot

    func fetchLatestRates() async throws -> ExchangeRateSnapshot {
        snapshot
    }
}
