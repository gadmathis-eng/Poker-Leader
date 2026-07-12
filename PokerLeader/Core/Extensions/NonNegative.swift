import Foundation

extension Decimal {
    var clampedToNonNegative: Decimal {
        self < 0 ? 0 : self
    }
}

extension Int {
    var clampedToNonNegative: Int {
        Swift.max(0, self)
    }
}
