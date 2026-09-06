import XCTest
@testable import PokerLeader

final class PokerTableSeatGeometryTests: XCTestCase {
    private let canvas = CGSize(width: 360, height: 560)
    private let seat = CGSize(width: 84, height: 86)

    func testSeatOneSitsAtTheBottomCenter() {
        let point = PokerTableSeatGeometry.center(
            forSeat: 1,
            of: 8,
            in: canvas,
            seatSize: seat
        )

        XCTAssertEqual(point.x, canvas.width / 2, accuracy: 1)
        XCTAssertGreaterThan(point.y, canvas.height * 0.8)
    }

    func testSeatFiveSitsAtTheTopCenter() {
        let point = PokerTableSeatGeometry.center(
            forSeat: 5,
            of: 8,
            in: canvas,
            seatSize: seat
        )

        XCTAssertEqual(point.x, canvas.width / 2, accuracy: 1)
        XCTAssertLessThan(point.y, canvas.height * 0.2)
    }

    func testSeatsWalkTheRailCounterclockwise() {
        let two = center(2)
        let four = center(4)
        let six = center(6)
        let eight = center(8)

        XCTAssertLessThan(two.x, canvas.width / 2)
        XCTAssertGreaterThan(two.y, canvas.height / 2)
        XCTAssertLessThan(four.x, canvas.width / 2)
        XCTAssertLessThan(four.y, canvas.height / 2)
        XCTAssertGreaterThan(six.x, canvas.width / 2)
        XCTAssertLessThan(six.y, canvas.height / 2)
        XCTAssertGreaterThan(eight.x, canvas.width / 2)
        XCTAssertGreaterThan(eight.y, canvas.height / 2)
    }

    func testSideSeatsSitOnTheLeftAndRightRails() {
        let three = center(3)
        let seven = center(7)

        XCTAssertEqual(three.y, canvas.height / 2, accuracy: 1)
        XCTAssertEqual(seven.y, canvas.height / 2, accuracy: 1)
        XCTAssertEqual(three.x, seat.width / 2, accuracy: 1)
        XCTAssertEqual(seven.x, canvas.width - seat.width / 2, accuracy: 1)
    }

    func testOppositeSeatsSitAcrossTheTable() {
        let one = center(1)
        let five = center(5)

        XCTAssertEqual(one.x, five.x, accuracy: 2)
        XCTAssertGreaterThan(one.y, five.y)
    }

    func testEverySeatHasADistinctPlaceOnTheRail() {
        let points = (1...8).map(center)
        for index in points.indices {
            for other in points.indices where other != index {
                let dx = points[index].x - points[other].x
                let dy = points[index].y - points[other].y
                XCTAssertGreaterThan(
                    (dx * dx + dy * dy).squareRoot(),
                    40,
                    "Seats \(index + 1) and \(other + 1) are too close"
                )
            }
        }
    }

    func testSeatCentersStayOnTheCanvas() {
        for number in 1...8 {
            let point = center(number)
            XCTAssertGreaterThanOrEqual(point.x, seat.width / 2 - 0.6)
            XCTAssertLessThanOrEqual(point.x, canvas.width - seat.width / 2 + 0.6)
            XCTAssertGreaterThanOrEqual(point.y, seat.height / 2 - 0.6)
            XCTAssertLessThanOrEqual(point.y, canvas.height - seat.height / 2 + 0.6)
        }
    }

    func testBottomCenterNormalizedPointMatchesSeatOne() {
        let rect = PokerTableSeatGeometry.railRect(in: canvas, seatSize: seat)
        let start = PokerTableSeatGeometry.point(
            atNormalized: 0,
            around: rect,
            cornerRadius: PokerTableSeatGeometry.cornerRadius(for: rect)
        )
        let seatOne = center(1)

        XCTAssertEqual(start.x, seatOne.x, accuracy: 0.01)
        XCTAssertEqual(start.y, seatOne.y, accuracy: 0.01)
        XCTAssertEqual(start.x, rect.midX, accuracy: 0.01)
        XCTAssertEqual(start.y, rect.maxY, accuracy: 0.01)
    }

    private func center(_ seatNumber: Int) -> CGPoint {
        PokerTableSeatGeometry.center(
            forSeat: seatNumber,
            of: 8,
            in: canvas,
            seatSize: seat
        )
    }
}
