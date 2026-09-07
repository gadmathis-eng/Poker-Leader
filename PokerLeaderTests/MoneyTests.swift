import XCTest
@testable import PokerLeader

final class MoneyTests: XCTestCase {
    func testDecimalsRoundToTheNearestCentRatherThanTruncating() {
        XCTAssertEqual(Money(decimal: Decimal(string: "10.005")!).cents, 1001)
        XCTAssertEqual(Money(decimal: Decimal(string: "10.004")!).cents, 1000)
        XCTAssertEqual(Money(decimal: Decimal(string: "0.1")!).cents, 10)
    }

    /// A third of a pot split three ways has to come back whole. This is the
    /// case integer cents exist to stop going wrong.
    func testSplittingAndRejoiningLosesNothing() {
        let pot = Money(cents: 10_000)
        let share = Money(cents: pot.cents / 3)
        let remainder = Money(cents: pot.cents - share.cents * 3)

        XCTAssertEqual(share + share + share + remainder, pot)
    }

    func testTypedInputIsParsed() {
        XCTAssertEqual(Money(userInput: "42.50")?.cents, 4250)
        XCTAssertEqual(Money(userInput: "7")?.cents, 700)
        XCTAssertEqual(Money(userInput: "$12.34")?.cents, 1234)
        XCTAssertNil(Money(userInput: ""))
        XCTAssertNil(Money(userInput: "abc"))
    }

    func testNegativeAmountsSurviveArithmetic() {
        XCTAssertEqual((-Money(cents: 250)).cents, -250)
        XCTAssertEqual((Money(cents: 100) - Money(cents: 250)).cents, -150)
        XCTAssertEqual(Money(cents: -150).magnitude, Money(cents: 150))
        XCTAssertEqual(Money(cents: -150).clampedToNonNegative(), .zero)
    }

    func testRoundTrippingThroughDecimalKeepsTheSameCents() {
        for cents in [0, 1, 99, 100, 12_345, -6_789] {
            XCTAssertEqual(Money(decimal: Money(cents: cents).decimalValue).cents, cents)
        }
    }
}
