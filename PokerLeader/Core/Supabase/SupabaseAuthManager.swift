import AuthenticationServices
import Foundation
import Supabase

@MainActor
@Observable
final class SupabaseAuthManager {
    static let shared = SupabaseAuthManager()

    private(set) var isSignedIn = false
    private(set) var userId: String?
    private(set) var email: String?

    private init() {}

    func refreshSession() async {
        guard SupabaseBootstrap.isConfigured, let client = SupabaseBootstrap.client else {
            isSignedIn = false
            userId = nil
            email = nil
            return
        }

        do {
            let session = try await client.auth.session
            apply(session: session)
        } catch {
            isSignedIn = false
            userId = nil
            email = nil
        }
    }

    func signInWithApple(idToken: String, fullName: PersonNameComponents?) async throws {
        let client = try SupabaseBootstrap.requireClient()
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken
            )
        )
        apply(session: session)

        if let fullName {
            var parts: [String] = []
            if let givenName = fullName.givenName { parts.append(givenName) }
            if let middleName = fullName.middleName { parts.append(middleName) }
            if let familyName = fullName.familyName { parts.append(familyName) }
            let fullNameString = parts.joined(separator: " ")
            guard !fullNameString.isEmpty else { return }

            try await client.auth.update(
                user: UserAttributes(
                    data: [
                        "full_name": .string(fullNameString),
                        "given_name": .string(fullName.givenName ?? ""),
                        "family_name": .string(fullName.familyName ?? "")
                    ]
                )
            )
        }
    }

    func sendEmailOTP(to email: String) async throws {
        let client = try SupabaseBootstrap.requireClient()
        try await client.auth.signInWithOTP(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            shouldCreateUser: true
        )
    }

    func verifyEmailOTP(email: String, token: String) async throws {
        let client = try SupabaseBootstrap.requireClient()
        let response = try await client.auth.verifyOTP(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            token: token.trimmingCharacters(in: .whitespacesAndNewlines),
            type: .email
        )
        guard let session = response.session else {
            throw SupabaseSyncError.notSignedIn
        }
        apply(session: session)
    }

    func signInWithGoogle() async throws {
        let client = try SupabaseBootstrap.requireClient()
        let session = try await client.auth.signInWithOAuth(
            provider: .google,
            redirectTo: SupabaseBootstrap.authRedirectURL
        )
        apply(session: session)
    }

    func handleOpenURL(_ url: URL) {
        guard let client = SupabaseBootstrap.client else { return }
        client.auth.handle(url)
        Task {
            await refreshSession()
        }
    }

    func signOut() async throws {
        let client = try SupabaseBootstrap.requireClient()
        try await client.auth.signOut()
        isSignedIn = false
        userId = nil
        email = nil
    }

    func deleteAccount() async throws {
        try await SupabaseSyncService.shared.deleteCurrentUserAccount()
        isSignedIn = false
        userId = nil
        email = nil
    }

    private func apply(session: Session) {
        isSignedIn = true
        userId = session.user.id.uuidString
        email = session.user.email
    }
}
