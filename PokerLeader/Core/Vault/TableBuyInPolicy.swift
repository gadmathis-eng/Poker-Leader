import Foundation

/// Turns a table's stake into the buy-in range the backend enforces.
///
/// Cloud tables settle in integer cents of the table's own currency. A keypad
/// that is showing a different display currency may convert *into* that table
/// unit so the player can type a familiar figure. Once the amount is in table
/// cents it is not converted again — not into the Vault's display currency,
/// and not back again after a receipt. `vaultAmount` / `tableAmount` stay for
/// local demo screens; they must not be used on the settlement path.
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
    /// Integer cents of the table's currency — the figure the backend moves.
    let amount: Money
    /// The same figure as a decimal, for putting chips on the seat.
    let tableAmount: Decimal
    let tableCurrencyCode: String
    let limits: TableBuyInLimits?
}
