import SwiftUI

struct PlayerAvatarView: View {
    let initial: String
    var size: CGFloat = 40

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.text)
            .frame(width: size, height: size)
            .background(Circle().fill(AppTheme.cardBorder))
    }
}
