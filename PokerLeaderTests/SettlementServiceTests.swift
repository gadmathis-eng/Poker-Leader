import XCTest
@testable import PokerLeader

final class SettlementServiceTests: XCTestCase {
    func testMinimumPaymentsExampleFromPDF() {
        let nets = [
            PlayerNet(id: UUID(), name: "Alex", initial: "A", net: 80),
            PlayerNet(id: UUID(), name: "Josh", initial: "J", net: 50),
            PlayerNet(id: UUID(), name: "Ben", initial: "B", net: -50),
            PlayerNet(id: UUID(), name: "Max", initial: "M", net: -80)
        ]
        let payments = SettlementService.minimumPayments(nets: nets)
        XCTAssertEqual(payments.count, 2)
        let total = payments.reduce(Decimal(0)) { $0 + $1.amount }
        XCTAssertEqual(total, 130)
    }
}
