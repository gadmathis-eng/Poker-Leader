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

/// One pull handle, in the same color as sheet titles, so it does not sit gray
/// against white copy. Use this instead of the system grabber.
struct SheetDragHandle: View {
    var body: some View {
        Capsule()
            .fill(AppTheme.text)
            .frame(width: 36, height: 5)
            .padding(.bottom, 6)
            .accessibilityHidden(true)
    }
}
