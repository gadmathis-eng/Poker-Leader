import Foundation

/// Turns a table's stake into the buy-in range the backend enforces, and moves
/// amounts between the table's currency and the Vault's.
///
/// The Vault settles in one currency; a table can be played in another. Rather
/// than let the two drift, everything the backend is asked to move is converted
/// into the Vault currency first, and the range is derived from the same
/// converted figure so a player is never shown a limit in one currency and
/// checked against it in another.
enum TableBuyInPolicy {
    /// A table takes at least half and at most four times the stake the host
    /// set, which is roughly how a home game already behaves.
    static func limits(forStandardBuyIn buyIn: Money) -> (minimum: Money, maximum: Money) {
        let floor = Money(cents: 100)
        let minimum = Money(cents: max(buyIn.cents / 2, floor.cents))
        let maximum = Money(cents: max(buyIn.cents * 4, minimum.cents))
        return (minimum, maximum)
    }

    static func vaultAmount(
        _ amount: Decimal,
        fromTableCurrency tableCurrencyCode: String,
        vaultCurrencyCode: String
    ) -> Money {
        Money(
            decimal: TableCurrencyConversion.amountInTableCurrency(
                amount,
                from: tableCurrencyCode,
                to: vaultCurrencyCode
            )
        )
    }

    /// The same conversion for a figure that is allowed to be negative. Buy-ins
    /// never are, but the change a hand makes to a stack usually is for somebody,
    /// and the shared conversion floors at zero — which would quietly turn every
    /// loss into nothing.
    static func vaultDelta(
        _ delta: Decimal,
        fromTableCurrency tableCurrencyCode: String,
        vaultCurrencyCode: String
    ) -> Money {
        let magnitude = vaultAmount(
            abs(delta),
            fromTableCurrency: tableCurrencyCode,
            vaultCurrencyCode: vaultCurrencyCode
        )
        return delta < 0 ? -magnitude : magnitude
    }

    static func tableAmount(
        _ money: Money,
        vaultCurrencyCode: String,
        toTableCurrency tableCurrencyCode: String
    ) -> Decimal {
        TableCurrencyConversion.amountInTableCurrency(
            money.decimalValue,
            from: vaultCurrencyCode,
            to: tableCurrencyCode
        )
    }
}

/// One buy-in waiting on payment. Held while the payment sheet is up so the
/// seat is not taken until the backend has verified the money.
struct PendingTableBuyIn: Identifiable, Equatable {
    var id: String { inviteCode + ":" + String(amount.cents) }
    let inviteCode: String
    let tableName: String
    /// In the Vault's currency, which is what the backend moves.
    let amount: Money
    /// In the table's currency, which is what goes on the felt.
    let tableAmount: Decimal
    let tableCurrencyCode: String
    let limits: TableBuyInLimits?
}
