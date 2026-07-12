import Foundation
import SwiftData

@Model
final class SettlementPaymentModel {
    @Attribute(.unique) var id: UUID
    var fromInitial: String
    var fromName: String
    var toInitial: String
    var toName: String
    var amount: Decimal {
        didSet { amount = amount.clampedToNonNegative }
    }

    var session: SessionModel?

    init(
        id: UUID = UUID(),
        fromInitial: String,
        fromName: String,
        toInitial: String,
        toName: String,
        amount: Decimal
    ) {
        self.id = id
        self.fromInitial = fromInitial
        self.fromName = fromName
        self.toInitial = toInitial
        self.toName = toName
        self.amount = amount.clampedToNonNegative
    }
}
