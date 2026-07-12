import SwiftUI

struct PotCheckBanner: View {
    let balanced: Bool
    let totalIn: Decimal
    let totalOut: Decimal
    let currencyCode: String

    var body: some View {
        VStack(spacing: 4) {
            Text("POT CHECK")
                .font(.caption2.weight(.bold))
                .tracking(AppTheme.sectionTracking)
                .foregroundStyle(AppTheme.muted)
            if balanced {
                Text("\(MoneyFormatting.plain(totalIn, currencyCode: currencyCode)) in · \(MoneyFormatting.plain(totalOut, currencyCode: currencyCode)) counted · Balanced")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.positive)
            } else {
                Text("\(MoneyFormatting.plain(totalIn, currencyCode: currencyCode)) in · \(MoneyFormatting.plain(totalOut, currencyCode: currencyCode)) counted")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.negative)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }
}
