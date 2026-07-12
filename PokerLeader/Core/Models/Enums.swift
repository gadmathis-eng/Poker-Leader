import Foundation

enum SessionStatus: String, Codable, CaseIterable {
    case setup
    case live
    case finalizing
    case settled
}

enum StreakType: String, Codable {
    case win
    case loss
}
