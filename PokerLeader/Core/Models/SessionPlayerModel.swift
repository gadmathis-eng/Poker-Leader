import Foundation
import SwiftData

@Model
final class SessionPlayerModel {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var initial: String
    var buyInCount: Int {
        didSet { buyInCount = buyInCount.clampedToNonNegative }
    }
    var totalIn: Decimal {
        didSet { totalIn = totalIn.clampedToNonNegative }
    }
    var finalOut: Decimal? {
        didSet { finalOut = finalOut?.clampedToNonNegative }
    }
    var net: Decimal?

    var session: SessionModel?
    var memberId: UUID?

    init(
        id: UUID = UUID(),
        displayName: String,
        initial: String,
        buyInCount: Int = 0,
        totalIn: Decimal = 0,
        finalOut: Decimal? = nil,
        net: Decimal? = nil,
        memberId: UUID? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.initial = initial
        self.buyInCount = buyInCount.clampedToNonNegative
        self.totalIn = totalIn.clampedToNonNegative
        self.finalOut = finalOut?.clampedToNonNegative
        self.net = net
        self.memberId = memberId
    }
}
