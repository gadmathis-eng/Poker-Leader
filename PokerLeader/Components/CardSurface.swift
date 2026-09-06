import SwiftUI

extension View {
    /// The rounded card the app is built out of: one fill, one hairline border.
    func cardSurface(padding: CGFloat = 14, cornerRadius: CGFloat = AppTheme.cornerRadius) -> some View {
        self
            .padding(padding)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(AppTheme.cardBorder)
            )
    }
}
