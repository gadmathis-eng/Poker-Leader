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

    func testTableNetsUseStackAgainstWhatEachPlayerPutIn() {
        let seats = [
            seat(1, name: "Ana", key: "ana", amount: "50", boughtIn: "20", isHost: true),
            seat(2, name: "Ben", key: "ben", amount: "10", boughtIn: "20"),
            seat(3, name: "Cal", key: "cal", amount: "20", boughtIn: "40")
        ]

        let nets = SettlementService.computeNets(seats: seats)
        XCTAssertEqual(nets.map(\.name), ["Ana", "Ben", "Cal"])
        XCTAssertEqual(nets.map(\.net), [30, -10, -20])

        let payments = SettlementService.minimumPayments(seats: seats)
        XCTAssertEqual(payments.count, 2)
        XCTAssertEqual(payments[0].fromName, "Cal")
        XCTAssertEqual(payments[0].toName, "Ana")
        XCTAssertEqual(payments[0].amount, 20)
        XCTAssertEqual(payments[1].fromName, "Ben")
        XCTAssertEqual(payments[1].toName, "Ana")
        XCTAssertEqual(payments[1].amount, 10)
    }

    func testEvenStacksMeanNobodyOwesAnybody() {
        let seats = [
            seat(1, name: "Ana", key: "ana", amount: "20", boughtIn: "20", isHost: true),
            seat(2, name: "Ben", key: "ben", amount: "20", boughtIn: "20")
        ]

        XCTAssertTrue(SettlementService.computeNets(seats: seats).allSatisfy { $0.net == 0 })
        XCTAssertTrue(SettlementService.minimumPayments(seats: seats).isEmpty)
    }

    func testAHandStillBeingPlayedGivesBetsBack() throws {
        var seats = [
            seat(1, name: "Ana", key: "ana", amount: "20", boughtIn: "20", isHost: true),
            seat(2, name: "Ben", key: "ben", amount: "20", boughtIn: "20")
        ]
        var hand = try HandRound.start(seats: seats, dealerSeat: 1, ante: 1)
        hand = try HandRound.apply(move: .call, playerKey: "ben", to: hand)

        XCTAssertGreaterThan(hand.pot, 0)
        XCTAssertEqual(SettlementService.cashOut(for: seats[0], hand: hand), 20)
        XCTAssertEqual(SettlementService.cashOut(for: seats[1], hand: hand), 20)
        XCTAssertTrue(SettlementService.minimumPayments(seats: seats, hand: hand).isEmpty)
    }

    func testAFinishedHandPaysTheWinner() throws {
        let seats = [
            seat(1, name: "Ana", key: "ana", amount: "20", boughtIn: "20", isHost: true),
            seat(2, name: "Ben", key: "ben", amount: "20", boughtIn: "20")
        ]
        var hand = try HandRound.start(seats: seats, dealerSeat: 1, ante: 1)
        hand = try HandRound.apply(move: .call, playerKey: "ben", to: hand)
        hand = try HandRound.apply(move: .call, playerKey: "ana", to: hand)
        hand = try HandRound.apply(move: .fold, playerKey: "ben", to: hand)

        XCTAssertTrue(hand.isComplete)
        XCTAssertEqual(SettlementService.cashOut(for: seats[0], hand: hand), 21)
        XCTAssertEqual(SettlementService.cashOut(for: seats[1], hand: hand), 19)

        let payments = SettlementService.minimumPayments(seats: seats, hand: hand)
        XCTAssertEqual(payments.count, 1)
        XCTAssertEqual(payments[0].fromName, "Ben")
        XCTAssertEqual(payments[0].toName, "Ana")
        XCTAssertEqual(payments[0].amount, 1)
    }

    func testAddingMoneyDoesNotChangeWhatIsOwed() {
        let seats = [
            seat(1, name: "Ana", key: "ana", amount: "31", boughtIn: "30", isHost: true),
            seat(2, name: "Ben", key: "ben", amount: "19", boughtIn: "20")
        ]

        let payments = SettlementService.minimumPayments(seats: seats)
        XCTAssertEqual(payments.count, 1)
        XCTAssertEqual(payments[0].fromName, "Ben")
        XCTAssertEqual(payments[0].toName, "Ana")
        XCTAssertEqual(payments[0].amount, 1)
    }

    func testTableSettlementMessageSaysWhoOwesWho() {
        let nets = [
            PlayerNet(id: UUID(), name: "Ana", initial: "A", net: 10),
            PlayerNet(id: UUID(), name: "Ben", initial: "B", net: -10)
        ]
        let payments = SettlementService.minimumPayments(nets: nets)
        let message = WhatsAppMessageBuilder.tableSettlementMessage(
            title: "Friday",
            currencyCode: "GBP",
            nets: nets,
            payments: payments
        )

        XCTAssertTrue(message.contains("Who owes who"))
        XCTAssertTrue(message.contains("Ben owes Ana £10"))
        XCTAssertTrue(message.contains("Ana +£10"))
        XCTAssertTrue(message.contains("Ben -£10"))
    }

    private func seat(
        _ number: Int,
        name: String,
        key: String,
        amount: String,
        boughtIn: String,
        isHost: Bool = false
    ) -> SharedTableSeat {
        SharedTableSeat(
            id: UUID(),
            seatNumber: number,
            playerName: name,
            handle: nil,
            playerKey: key,
            amount: amount,
            boughtIn: boughtIn,
            isHost: isHost
        )
    }
}
