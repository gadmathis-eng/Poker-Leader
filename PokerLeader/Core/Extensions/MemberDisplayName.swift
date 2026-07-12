import Foundation

extension MemberModel {
    func displayName(preferredHandle: String?) -> String {
        if isCurrentUser, Self.isPlaceholderName(displayName) {
            return Self.normalizedHandle(preferredHandle) ?? "Your name"
        }

        return displayName
    }

    static func isPlaceholderName(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "you" || normalized == "your name"
    }

    static func isPlaceholderHandle(_ handle: String?) -> Bool {
        let normalized = normalizedHandle(handle)?.lowercased()
        return normalized == nil || normalized == "@yourname"
    }

    static func normalizedHandle(_ handle: String?) -> String? {
        guard var cleaned = handle?.trimmingCharacters(in: .whitespacesAndNewlines), !cleaned.isEmpty else {
            return nil
        }
        if !cleaned.hasPrefix("@") {
            cleaned = "@\(cleaned)"
        }
        return cleaned
    }

    static func generatedUniqueHandle(
        for displayName: String,
        existingHandles: Set<String>
    ) -> String {
        let base = handleBase(for: displayName)
        var candidate = "@\(base)"
        var suffix = 2
        let normalizedExistingHandles = Set(existingHandles.map { $0.lowercased() })

        while normalizedExistingHandles.contains(candidate.lowercased()) {
            candidate = "@\(base)\(suffix)"
            suffix += 1
        }

        return candidate
    }

    static func handleBase(for displayName: String) -> String {
        let allowedCharacters = displayName
            .lowercased()
            .filter { character in
                character.isLetter || character.isNumber || character == "_"
            }

        return allowedCharacters.isEmpty ? "player" : String(allowedCharacters)
    }
}
