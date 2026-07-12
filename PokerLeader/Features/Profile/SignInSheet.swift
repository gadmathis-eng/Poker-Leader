import AuthenticationServices
import SwiftUI

struct SignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("displayName") private var displayName = "Your name"
    @AppStorage("playerHandle") private var playerHandle = "@yourname"

    @State private var email = ""
    @State private var otpCode = ""
    @State private var otpSent = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var allowsOfflineContinue = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sign in to sync")
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.text)
                        Text("Use the same account on every device to pull your circles, sessions, and friend requests.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                    }

                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.email, .fullName]
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    .disabled(isWorking)

                    SignInWithGoogleButton(isDisabled: isWorking) {
                        Task { await handleGoogleSignIn() }
                    }

                    HStack {
                        Rectangle().fill(AppTheme.cardBorder).frame(height: 1)
                        Text("or email")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                        Rectangle().fill(AppTheme.cardBorder).frame(height: 1)
                    }

                    VStack(spacing: 0) {
                        TextField("Email address", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .padding()
                            .foregroundStyle(AppTheme.text)
                            .disabled(otpSent || isWorking)

                        if otpSent {
                            Divider().overlay(AppTheme.cardBorder)
                            TextField("6-digit code", text: $otpCode)
                                .keyboardType(.numberPad)
                                .padding()
                                .foregroundStyle(AppTheme.text)
                                .disabled(isWorking)
                        }
                    }
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

                    Button {
                        Task { await handleEmailAction() }
                    } label: {
                        Text(emailActionTitle)
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isWorking ? AppTheme.card : AppTheme.positive)
                            .foregroundStyle(isWorking ? AppTheme.muted : AppTheme.contrastText)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking || !canSubmitEmailAction)

                    if otpSent {
                        Button("Use a different email") {
                            otpSent = false
                            otpCode = ""
                            errorMessage = nil
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(AppTheme.negative)
                    }

                    if allowsOfflineContinue {
                        Button("Continue without signing in") {
                            dismiss()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if allowsOfflineContinue {
                        Button("Close") { dismiss() }
                    }
                }
            }
        }
    }

    private var emailActionTitle: String {
        if isWorking {
            return otpSent ? "Verifying..." : "Sending code..."
        }
        return otpSent ? "Verify code" : "Send sign-in code"
    }

    private var canSubmitEmailAction: Bool {
        if otpSent {
            return otpCode.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6
        }
        return email.contains("@")
    }

    private func handleGoogleSignIn() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await SupabaseAuthManager.shared.signInWithGoogle()
            await completeSignIn()
        } catch {
            if isUserCancelledAuthError(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func isUserCancelledAuthError(_ error: Error) -> Bool {
        if (error as NSError).domain == ASAuthorizationError.errorDomain,
           (error as NSError).code == ASAuthorizationError.canceled.rawValue {
            return true
        }

        if let authError = error as? ASWebAuthenticationSessionError,
           authError.code == .canceledLogin {
            return true
        }

        return false
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        Task {
            isWorking = true
            errorMessage = nil
            defer { isWorking = false }

            do {
                let authorization = try result.get()
                guard
                    let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                    let idTokenData = credential.identityToken,
                    let idToken = String(data: idTokenData, encoding: .utf8)
                else {
                    errorMessage = "Apple sign-in did not return a valid token."
                    return
                }

                try await SupabaseAuthManager.shared.signInWithApple(
                    idToken: idToken,
                    fullName: credential.fullName
                )
                await completeSignIn()
            } catch {
                if isUserCancelledAuthError(error) {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleEmailAction() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            if otpSent {
                try await SupabaseAuthManager.shared.verifyEmailOTP(email: email, token: otpCode)
                await completeSignIn()
            } else {
                try await SupabaseAuthManager.shared.sendEmailOTP(to: email)
                otpSent = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func completeSignIn() async {
        await CloudSyncCoordinator.restoreAccountAndSync(context: context)

        if
            let handle = MemberModel.normalizedHandle(playerHandle),
            !MemberModel.isPlaceholderHandle(handle),
            !MemberModel.isPlaceholderName(displayName)
        {
            try? await SupabaseSyncService.shared.upsertUserProfile(
                handle: handle,
                displayName: displayName
            )
        }

        dismiss()
    }
}
