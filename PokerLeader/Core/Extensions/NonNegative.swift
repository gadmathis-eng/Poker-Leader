import Foundation

extension Decimal {
    var clampedToNonNegative: Decimal {
        self < 0 ? 0 : self
    }

    var roundedToHundredths: Decimal {
        var value = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return rounded
    }
}

extension Int {
    var clampedToNonNegative: Int {
        Swift.max(0, self)
    }
}
