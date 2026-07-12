import Foundation
import SwiftData

@Model
final class SessionModel {
    @Attribute(.unique) var id: UUID
    var title: String
    var statusRaw: String
    var buyInAmount: Decimal {
        didSet { buyInAmount = buyInAmount.clampedToNonNegative }
    }
    var currencyCode: String
    var potTotal: Decimal {
        didSet { potTotal = potTotal.clampedToNonNegative }
    }
    var startedAt: Date
    var endedAt: Date?
    var summaryLine: String?

    var circle: CircleModel?

    @Relationship(deleteRule: .cascade, inverse: \SessionPlayerModel.session)
    var players: [SessionPlayerModel]

    @Relationship(deleteRule: .cascade, inverse: \SettlementPaymentModel.session)
    var payments: [SettlementPaymentModel]

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .live }
        set { statusRaw = newValue.rawValue }
    }

    func displayTitle(in circle: CircleModel) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Friday Night Poker" {
            return circle.name
        }
        return trimmed
    }

    init(
        id: UUID = UUID(),
        title: String,
        status: SessionStatus = .live,
        buyInAmount: Decimal,
        currencyCode: String = "GBP",
        potTotal: Decimal = 0,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        summaryLine: String? = nil,
        players: [SessionPlayerModel] = [],
        payments: [SettlementPaymentModel] = []
    ) {
        self.id = id
        self.title = title
        self.statusRaw = status.rawValue
        self.buyInAmount = buyInAmount.clampedToNonNegative
        self.currencyCode = currencyCode
        self.potTotal = potTotal.clampedToNonNegative
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.summaryLine = summaryLine
        self.players = players
        self.payments = payments
    }
}
