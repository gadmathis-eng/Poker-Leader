import XCTest
@testable import PokerLeader

final class MoneyAmountKeypadTests: XCTestCase {
    func testNormalizedTextTreatsBlankAsZero() {
        XCTAssertEqual(MoneyAmountKeypad.normalizedText(""), "0")
        XCTAssertEqual(MoneyAmountKeypad.normalizedText("   "), "0")
    }

    func testNormalizedTextStripsTrailingDecimal() {
        XCTAssertEqual(MoneyAmountKeypad.normalizedText("20."), "20")
    }

    func testCommittedTextClampsToMaximum() {
        XCTAssertEqual(MoneyAmountKeypad.committedText("50", maximum: 20), "20")
    }

    func testCommittedTextKeepsValueWithinMaximum() {
        XCTAssertEqual(MoneyAmountKeypad.committedText("12.5", maximum: 20), "12.5")
    }

    func testCommittedTextAllowsAnyAmountWithoutMaximum() {
        XCTAssertEqual(MoneyAmountKeypad.committedText("75.25", maximum: nil), "75.25")
    }
}
