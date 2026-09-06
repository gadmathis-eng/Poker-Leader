import SwiftUI
import UIKit

struct InviteCodeCopyLabel: View {
    enum Style {
        case badge
        case compact
        case headline
    }

    let code: String
    var style: Style = .badge
    /// What the badge sits on, so the chip still reads when it is inside a card.
    var fill: Color = AppTheme.card

    @State private var didCopy = false

    var body: some View {
        Button(action: copyCode) {
            labelContent
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: didCopy)
        .accessibilityLabel("Invite code \(code)")
        .accessibilityHint(didCopy ? "Copied" : "Copies invite code")
    }

    @ViewBuilder
    private var labelContent: some View {
        switch style {
        case .badge:
            HStack(spacing: 6) {
                Text(code)
                    .font(.caption.weight(.bold))
                copyIndicator
            }
            .padding(8)
            .background(fill)
            .foregroundStyle(AppTheme.text)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        case .compact:
            HStack(spacing: 4) {
                Text(code)
                    .font(.subheadline.weight(.bold).monospaced())
                copyIndicator
            }
            .foregroundStyle(AppTheme.text)
        case .headline:
            HStack(spacing: 8) {
                Text(code)
                    .font(.title2.weight(.heavy))
                copyIndicator
            }
            .foregroundStyle(AppTheme.text)
        }
    }

    private var copyIndicator: some View {
        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
            .font(indicatorFont)
            .foregroundStyle(didCopy ? AppTheme.positive : AppTheme.muted)
    }

    private var indicatorFont: Font {
        switch style {
        case .badge:
            return .caption2.weight(.bold)
        case .compact:
            return .caption.weight(.bold)
        case .headline:
            return .subheadline.weight(.semibold)
        }
    }

    private func copyCode() {
        UIPasteboard.general.string = code
        didCopy = true

        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}
