import CoreGraphics
import Foundation

/// Places seats on the rail of a rounded-rect table.
///
/// Seat 1 sits at the bottom center. The rest walk the rail counterclockwise
/// (up the left side, across the top, down the right), like a live poker room.
enum PokerTableSeatGeometry {
    /// How round the table corners are, as a fraction of the shorter side.
    static let cornerFraction: CGFloat = 0.32

    static func center(
        forSeat seat: Int,
        of seatCount: Int,
        in size: CGSize,
        seatSize: CGSize
    ) -> CGPoint {
        let count = max(seatCount, 1)
        let index = ((seat - 1) % count + count) % count
        let t = CGFloat(index) / CGFloat(count)
        return pointOnRail(at: t, in: size, seatSize: seatSize)
    }

    static func railRect(in size: CGSize, seatSize: CGSize) -> CGRect {
        CGRect(
            x: seatSize.width / 2,
            y: seatSize.height / 2,
            width: max(size.width - seatSize.width, 1),
            height: max(size.height - seatSize.height, 1)
        )
    }

    static func cornerRadius(for rect: CGRect) -> CGFloat {
        min(rect.width, rect.height) * cornerFraction
    }

    static func pointOnRail(at t: CGFloat, in size: CGSize, seatSize: CGSize) -> CGPoint {
        let rect = railRect(in: size, seatSize: seatSize)
        return point(atNormalized: t, around: rect, cornerRadius: cornerRadius(for: rect))
    }

    /// `t` of 0 is the bottom center. Values then walk the rail counterclockwise.
    static func point(atNormalized t: CGFloat, around rect: CGRect, cornerRadius: CGFloat) -> CGPoint {
        let radius = min(max(cornerRadius, 0), min(rect.width, rect.height) / 2)
        let segments = railSegments(around: rect, cornerRadius: radius)
        let total = segments.reduce(0) { $0 + $1.length }
        guard total > 0 else {
            return CGPoint(x: rect.midX, y: rect.maxY)
        }

        var remaining = wrappedUnit(t) * total
        for segment in segments where segment.length > 0 {
            if remaining <= segment.length {
                return segment.point(at: remaining / segment.length)
            }
            remaining -= segment.length
        }
        return segments.last?.point(at: 1) ?? CGPoint(x: rect.midX, y: rect.maxY)
    }

    private static func wrappedUnit(_ t: CGFloat) -> CGFloat {
        let wrapped = t.truncatingRemainder(dividingBy: 1)
        return wrapped < 0 ? wrapped + 1 : wrapped
    }

    private static func railSegments(around rect: CGRect, cornerRadius r: CGFloat) -> [RailSegment] {
        let left = rect.minX
        let right = rect.maxX
        let top = rect.minY
        let bottom = rect.maxY
        let midX = rect.midX
        let straightWidth = max(rect.width - 2 * r, 0)
        let straightHeight = max(rect.height - 2 * r, 0)
        let arc = CGFloat.pi / 2 * r

        return [
            RailSegment(length: straightWidth / 2) { u in
                CGPoint(x: midX - straightWidth / 2 * u, y: bottom)
            },
            RailSegment(length: arc) { u in
                arcPoint(center: CGPoint(x: left + r, y: bottom - r), radius: r, start: .pi / 2, sweep: .pi / 2, u: u)
            },
            RailSegment(length: straightHeight) { u in
                CGPoint(x: left, y: bottom - r - straightHeight * u)
            },
            RailSegment(length: arc) { u in
                arcPoint(center: CGPoint(x: left + r, y: top + r), radius: r, start: .pi, sweep: .pi / 2, u: u)
            },
            RailSegment(length: straightWidth) { u in
                CGPoint(x: left + r + straightWidth * u, y: top)
            },
            RailSegment(length: arc) { u in
                arcPoint(center: CGPoint(x: right - r, y: top + r), radius: r, start: 3 * .pi / 2, sweep: .pi / 2, u: u)
            },
            RailSegment(length: straightHeight) { u in
                CGPoint(x: right, y: top + r + straightHeight * u)
            },
            RailSegment(length: arc) { u in
                arcPoint(center: CGPoint(x: right - r, y: bottom - r), radius: r, start: 0, sweep: .pi / 2, u: u)
            },
            RailSegment(length: straightWidth / 2) { u in
                CGPoint(x: right - r - straightWidth / 2 * u, y: bottom)
            }
        ]
    }

    private static func arcPoint(
        center: CGPoint,
        radius: CGFloat,
        start: CGFloat,
        sweep: CGFloat,
        u: CGFloat
    ) -> CGPoint {
        let angle = start + sweep * u
        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }
}

private struct RailSegment {
    var length: CGFloat
    var point: (CGFloat) -> CGPoint

    func point(at u: CGFloat) -> CGPoint {
        point(min(max(u, 0), 1))
    }
}
