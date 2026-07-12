import SwiftUI
import UIKit

struct InviteCodeCopyLabel: View {
    enum Style {
        case badge
        case headline
    }

    let code: String
    var style: Style = .badge

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
            .background(AppTheme.card)
            .foregroundStyle(AppTheme.text)
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
            .font(style == .headline ? .subheadline.weight(.semibold) : .caption2.weight(.bold))
            .foregroundStyle(didCopy ? AppTheme.positive : AppTheme.muted)
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
