import SwiftUI

struct CircleCardView: View {
    let circle: CircleModel
    let yourNet: Decimal
    let currentUserLabel: String
    let memberInitials: [String]
    let lastPlayedText: String
    var showsInviteShare: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(circle.shortCode)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
                    .padding(8)
                    .background(AppTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading) {
                    Text(circle.name)
                        .font(.headline)
                        .foregroundStyle(AppTheme.text)
                    Text("\(circle.memberCount) members · \(circle.gameCount) games")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    if showsInviteShare {
                        ShareLink(
                            item: CircleInviteSharing.url(for: circle),
                            subject: Text("Join \(circle.name) on Pot Master"),
                            message: Text(CircleInviteSharing.message(for: circle))
                        ) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.positive)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.background)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    MoneyText(amount: yourNet, currencyCode: circle.currencyCode)
                    Text("\(currentUserLabel) net")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                }
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
                Text("Played \(lastPlayedText)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .padding()
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.cardBorder))
    }
}
