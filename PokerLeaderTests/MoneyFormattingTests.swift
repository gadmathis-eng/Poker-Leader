import XCTest
@testable import PokerLeader

final class MoneyFormattingTests: XCTestCase {
    func testPlainAmountsUseCurrencySymbols() {
        XCTAssertEqual(MoneyFormatting.plain(0, currencyCode: "USD"), "$0")
        XCTAssertEqual(MoneyFormatting.plain(0, currencyCode: "GBP"), "£0")
        XCTAssertEqual(MoneyFormatting.plain(0, currencyCode: "EUR"), "€0")
        XCTAssertEqual(MoneyFormatting.plain(0, currencyCode: "ILS"), "₪0")
        XCTAssertEqual(MoneyFormatting.plain(0, currencyCode: "AED"), "د.إ0")
    }

    func testSignedAmountsUseCurrencySymbols() {
        XCTAssertEqual(MoneyFormatting.format(12, currencyCode: "USD"), "+$12")
        XCTAssertEqual(MoneyFormatting.format(-12, currencyCode: "GBP"), "-£12")
        XCTAssertEqual(MoneyFormatting.format(0, currencyCode: "EUR"), "€0")
    }

    func testUnknownCurrencyFallsBackToCodePrefix() {
        XCTAssertEqual(MoneyFormatting.plain(0, currencyCode: "XXX"), "XXX 0")
    }
}
