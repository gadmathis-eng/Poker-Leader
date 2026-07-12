import SwiftUI

struct BoardCirclePickerRow: View {
    let circle: CircleModel
    let yourNet: Decimal
    let currentUserLabel: String
    let leaderName: String?
    let leaderNet: Decimal?
    let memberInitials: [String]
    let lastPlayedText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(circle.shortCode)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
                    .padding(8)
                    .background(AppTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(circle.name)
                        .font(.headline)
                        .foregroundStyle(AppTheme.text)
                    Text("\(circle.memberCount) members · \(circle.gameCount) games")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
            }

            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(memberInitials.enumerated()), id: \.offset) { _, initial in
                            PlayerAvatarView(initial: initial, size: 28)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    MoneyText(amount: yourNet, currencyCode: circle.currencyCode)
                    Text("\(currentUserLabel) net")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                }
            }

            if let leaderName, let leaderNet {
                HStack {
                    Image(systemName: "trophy.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.gold)
                    Text("\(leaderName) leads with")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                    MoneyText(amount: leaderNet, currencyCode: circle.currencyCode)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("Played \(lastPlayedText)")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                }
            }
        }
        .padding()
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.cardBorder)
        )
    }
}
