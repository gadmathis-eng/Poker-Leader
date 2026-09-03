import SwiftUI

struct CircleOvalTableView: View {
    let circle: CircleModel
    var liveSession: SessionModel?

    var body: some View {
        ZStack {
            PokerTableGraphic(lineWidth: 2.5, innerLineWidth: 1.5)
                .padding(.horizontal, 8)

            VStack(spacing: 6) {
                Text(circle.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if let liveSession {
                    Text("LIVE")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(AppTheme.positive)
                    MoneyText(amount: liveSession.potTotal, currencyCode: liveSession.currencyCode)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.gold)
                } else {
                    Text(circle.shortCode)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
