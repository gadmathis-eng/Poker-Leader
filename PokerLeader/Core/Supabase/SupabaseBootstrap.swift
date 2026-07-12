import Foundation
import Supabase

enum SupabaseBootstrap {
    static let missingConfigurationMessage = "Add Supabase.plist with your project URL and anon key to enable cloud sync."

    static let authRedirectURL = URL(string: "com.mathisgad.pokerleader://auth-callback")!

    private(set) static var client: SupabaseClient?

    @discardableResult
    static func configureIfPossible() -> Bool {
        if client != nil { return true }

        guard
            let urlString = loadValue(key: "SUPABASE_URL"),
            let key = loadValue(key: "SUPABASE_ANON_KEY"),
            let url = URL(string: urlString)
        else {
            return false
        }

        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(redirectToURL: authRedirectURL)
            )
        )
        return true
    }

    static var isConfigured: Bool {
        client != nil
    }

    static func requireClient() throws -> SupabaseClient {
        guard configureIfPossible(), let client else {
            throw SupabaseSyncError.notConfigured
        }
        return client
    }

    private static func loadPlistDictionary() -> [String: Any]? {
        if let url = Bundle.main.url(forResource: "Supabase", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            return plist
        }

        if let path = Bundle.main.path(forResource: "Supabase", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path) as? [String: Any] {
            return plist
        }

        return nil
    }

    private static func loadValue(key: String) -> String? {
        guard let dict = loadPlistDictionary() else {
            return nil
        }

        guard
            let value = dict[key] as? String,
            !value.isEmpty,
            !value.hasPrefix("YOUR_")
        else {
            return nil
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
