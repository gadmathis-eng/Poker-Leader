import SwiftUI

enum AppAppearancePreference: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var iconName: String {
        switch self {
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum AppTheme {
    static let background = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let cardBorder = Color.primary.opacity(0.08)
    static let text = Color.primary
    static let muted = Color.secondary
    static let contrastText = Color.black
    static let positive = Color(red: 0.28, green: 0.82, blue: 0.52)
    static let negative = Color(red: 0.95, green: 0.38, blue: 0.38)
    static let gold = Color(red: 0.95, green: 0.78, blue: 0.35)

    static let sectionTracking: CGFloat = 2
    static let cornerRadius: CGFloat = 14
}
