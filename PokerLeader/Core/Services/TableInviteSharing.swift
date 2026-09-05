import Foundation

enum TableInviteDeepLink {
    static let httpsHost = "potmaster.app"
    static let webBaseURL = URL(string: "https://potmaster.app")!

    static func webURL(forInviteCode code: String) -> URL {
        let normalized = normalizedCode(code)
        return URL(string: "https://\(httpsHost)/?table=\(normalized)")!
    }

    static func appURL(forInviteCode code: String) -> URL {
        let normalized = normalizedCode(code)
        return URL(string: "\(CircleInviteDeepLink.scheme)://table/\(normalized)")!
    }

    static func inviteCode(from url: URL) -> String? {
        if let code = appInviteCode(from: url) {
            return code
        }
        return webInviteCode(from: url)
    }

    static func normalizedCode(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Accepts a 6-character code, a share URL, or the share message itself.
    static func pastedInviteCode(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        for candidate in [trimmed, "https://\(trimmed)"] {
            if let url = URL(string: candidate), let code = inviteCode(from: url) {
                return code
            }
        }

        let tokens = normalizedCode(trimmed)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        if let marker = tokens.firstIndex(where: { $0 == "TABLE" || $0 == "CODE" }),
           tokens.index(after: marker) < tokens.endIndex {
            let next = tokens[tokens.index(after: marker)]
            if (4...8).contains(next.count) {
                return next
            }
        }

        if let token = tokens.last(where: { (4...8).contains($0.count) }) {
            return token
        }

        return normalizedCode(trimmed)
    }

    private static func appInviteCode(from url: URL) -> String? {
        guard url.scheme?.caseInsensitiveCompare(CircleInviteDeepLink.scheme) == .orderedSame else {
            return nil
        }
        guard url.host?.lowercased() == "table" else { return nil }

        let pathCode = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !pathCode.isEmpty {
            return normalizedCode(pathCode)
        }

        return queryCode(from: url)
    }

    private static func webInviteCode(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "https" else { return nil }

        let host = url.host?.lowercased() ?? ""
        guard host == httpsHost || host == "www.\(httpsHost)" else { return nil }

        if let queryCode = queryCode(from: url) {
            return queryCode
        }

        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard let first = parts.first, first.lowercased() == "table" else { return nil }

        if parts.count >= 2, !parts[1].isEmpty {
            return normalizedCode(parts[1])
        }

        return nil
    }

    private static func queryCode(from url: URL) -> String? {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let items = components.queryItems
        else {
            return nil
        }

        for name in ["table", "code"] {
            if let code = items.first(where: { $0.name == name })?.value, !code.isEmpty {
                return normalizedCode(code)
            }
        }

        return nil
    }
}

enum TableInviteSharing {
    static func url(forInviteCode code: String) -> URL {
        TableInviteDeepLink.webURL(forInviteCode: code)
    }

    static func message(forInviteCode code: String, hostName: String) -> String {
        let trimmedName = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = MemberModel.isPlaceholderName(trimmedName) ? "my" : "\(trimmedName)'s"
        let normalized = TableInviteDeepLink.normalizedCode(code)
        let link = url(forInviteCode: normalized).absoluteString
        return """
        Join \(host) Pot Master table!

        Table code: \(normalized)
        Tap to sit down: \(link)
        """
    }
}
