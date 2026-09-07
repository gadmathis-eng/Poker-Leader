import XCTest
@testable import PokerLeader

final class VaultFXTests: XCTestCase {
    func testPublishedUSDToGBPRate() {
        XCTAssertEqual(VaultFX.convert(cents: 10_000, from: "USD", to: "GBP"), 7_900)
        XCTAssertEqual(VaultFX.convert(cents: 7_900, from: "GBP", to: "USD"), 10_000)
    }

    func testSameCurrencyIsANoOp() {
        XCTAssertEqual(VaultFX.convert(cents: 2_000, from: "usd", to: "USD"), 2_000)
    }

    func testHalfAwayFromZeroMatchesPostgresRound() {
        // 2000 / 0.79 = 2531.645… → 2532
        XCTAssertEqual(VaultFX.convert(cents: 2_000, from: "GBP", to: "USD"), 2_532)
    }

    func testUnknownCurrencyReturnsNil() {
        XCTAssertNil(VaultFX.convert(cents: 100, from: "USD", to: "XXX"))
    }
}
