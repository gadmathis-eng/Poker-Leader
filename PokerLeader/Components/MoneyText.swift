import SwiftUI

struct MoneyText: View {
    let amount: Decimal
    var currencyCode: String = "GBP"
    var showSign: Bool = true

    var body: some View {
        Text(showSign ? MoneyFormatting.format(amount, currencyCode: currencyCode) : MoneyFormatting.plain(amount, currencyCode: currencyCode))
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(amount >= 0 ? AppTheme.positive : AppTheme.negative)
    }
}
