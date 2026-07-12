import SwiftUI

struct PlayerRowView: View {
    let name: String
    let initial: String
    let subtitle: String
    var trailing: AnyView?

    var body: some View {
        HStack(spacing: 12) {
            PlayerAvatarView(initial: initial)
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.text)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
            if let trailing { trailing }
        }
        .padding()
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).stroke(AppTheme.cardBorder))
    }
}
