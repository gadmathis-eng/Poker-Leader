import XCTest
@testable import PokerLeader

final class VaultFXTests: XCTestCase {
    func testPublishedUSDToGBPRate() {
        XCTAssertEqual(VaultFX.convert(cents: 10_000, from: "USD", to: "GBP"), 7_900)
        XCTAssertEqual(VaultFX.convert(cents: 7_900, from: "GBP", to: "USD"), 10_000)
    }

    func testSameCurrencyIsANoOp() {
        XCTAssertEqual(VaultFX.convert(cents: 2_000, from: "usd", to: "USD"), 2_000)
        XCTAssertEqual(VaultFX.convert(cents: 2_000, from: "eur", to: "EUR"), 2_000)
        XCTAssertEqual(VaultFX.convert(cents: 2_000, from: "jpy", to: "JPY"), 2_000)
    }

    func testHalfAwayFromZeroMatchesPostgresRound() {
        // 2000 / 0.79 = 2531.645… → 2532
        XCTAssertEqual(VaultFX.convert(cents: 2_000, from: "GBP", to: "USD"), 2_532)
    }

    func testConvertsAnyPublishedPairNotJustUSDAndGBP() {
        XCTAssertEqual(VaultFX.convert(cents: 10_000, from: "USD", to: "EUR"), 9_200)
        XCTAssertEqual(VaultFX.convert(cents: 10_000, from: "EUR", to: "USD"), 10_870)
        XCTAssertEqual(VaultFX.convert(cents: 10_000, from: "USD", to: "JPY"), 1_570_000)
        XCTAssertEqual(VaultFX.convert(cents: 2_000, from: "ILS", to: "CAD"), 731)
        XCTAssertEqual(VaultFX.convert(cents: 1_360, from: "CAD", to: "AUD"), 1_510)
    }

    func testEveryPublishedCurrencyConvertsToUSDAndBack() {
        for code in VaultFX.supportedCurrencyCodes {
            XCTAssertNotNil(VaultFX.convert(cents: 10_000, from: "USD", to: code), code)
            XCTAssertNotNil(VaultFX.convert(cents: 10_000, from: code, to: "USD"), code)
            XCTAssertTrue(VaultFX.supports(code), code)
        }

        for code in ["USD", "GBP", "EUR", "ILS", "CAD", "AUD"] {
            XCTAssertTrue(VaultFX.supports(code), code)
        }
    }

    func testUnknownCurrencyReturnsNil() {
        XCTAssertNil(VaultFX.convert(cents: 100, from: "USD", to: "XXX"))
        XCTAssertFalse(VaultFX.supports("XXX"))
    }
}
