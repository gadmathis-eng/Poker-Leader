import Foundation

enum CircleInviteDeepLink {
    static let scheme = "com.mathisgad.pokerleader"

    static func url(forInviteCode code: String) -> URL {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return URL(string: "\(scheme)://join/\(normalized)")!
    }

    static func inviteCode(from url: URL) -> String? {
        guard url.scheme?.caseInsensitiveCompare(scheme) == .orderedSame else { return nil }
        guard url.host?.lowercased() == "join" else { return nil }

        let pathCode = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !pathCode.isEmpty {
            return pathCode.uppercased()
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
           !code.isEmpty {
            return code.uppercased()
        }

        return nil
    }

    static func url(forSettlement sessionId: UUID) -> URL {
        URL(string: "\(scheme)://settlement/\(sessionId.uuidString.lowercased())")!
    }

    static func settlementSessionId(from url: URL) -> UUID? {
        guard url.scheme?.caseInsensitiveCompare(scheme) == .orderedSame else { return nil }
        guard url.host?.lowercased() == "settlement" else { return nil }

        let idString = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !idString.isEmpty else { return nil }
        return UUID(uuidString: idString)
    }
}

enum CircleInviteSharing {
    static func url(for circle: CircleModel) -> URL {
        CircleInviteDeepLink.url(forInviteCode: circle.shortCode)
    }

    static func message(for circle: CircleModel) -> String {
        let link = url(for: circle).absoluteString
        return """
        Join my Pot Master circle "\(circle.name)"!

        Tap to join: \(link)

        Or use invite code: \(circle.shortCode)
        """
    }

    static func sessionSetupMessage(
        for circle: CircleModel,
        title: String,
        buyInAmount: Decimal,
        currencyCode: String
    ) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionTitle = trimmedTitle.isEmpty ? "New session" : trimmedTitle
        let buyIn = MoneyFormatting.plain(buyInAmount, currencyCode: currencyCode)
        let link = url(for: circle).absoluteString

        return """
        Join our Pot Master session in "\(circle.name)"!

        Session: \(sessionTitle)
        Buy-in: \(buyIn)

        Tap to join: \(link)

        Or use invite code: \(circle.shortCode)
        """
    }
}

enum SettlementSharing {
    static func appURL(for sessionId: UUID) -> URL {
        CircleInviteDeepLink.url(forSettlement: sessionId)
    }

    static func appLinkMessage(for sessionId: UUID) -> String {
        """
        Open in Pot Master:
        \(appURL(for: sessionId).absoluteString)
        """
    }
}
