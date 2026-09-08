import Foundation
import Supabase

/// The client half of Stripe. It does not talk to Stripe's API and it does not
/// hold a secret key. When enabled, it hands the Apple Pay token to the
/// `stripe-apple-pay` Edge Function, which charges the amount already stored on
/// the Vault intent and asks the backend to settle.
///
/// Off by default. Turn on with `STRIPE_VAULT_ENABLED=YES` in `Supabase.plist`
/// after the functions are deployed. See Docs/Payments.md.
enum StripeVaultGateway {
    static var isEnabled: Bool {
        SupabaseBootstrap.isStripeVaultEnabled && SupabaseBootstrap.isConfigured
    }

    /// Simulator and mock tokens are not payment data. Stripe will reject them;
    /// we reject them first so the player sees why.
    static func isChargeableApplePayToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("demo_tok_") { return false }
        if trimmed.hasPrefix("pk_tok_") { return false }
        return true
    }

    @MainActor
    static func confirmApplePay(
        intentID: UUID,
        authorization: PaymentAuthorization
    ) async throws -> DepositIntent {
        guard isEnabled else {
            throw VaultError.backend("Stripe is not enabled in Supabase.plist.")
        }
        guard isChargeableApplePayToken(authorization.providerToken) else {
            throw VaultError.paymentFailed(
                "Stripe cannot charge a test Apple Pay token. Run on an iPhone with Wallet set up."
            )
        }

        let client = try SupabaseBootstrap.requireClient()
        let data = try JSONEncoder().encode(
            ConfirmBody(
                vault_intent_id: intentID,
                apple_pay_token: authorization.providerToken
            )
        )

        do {
            let row: IntentResponse = try await client.functions.invoke(
                "stripe-apple-pay",
                options: FunctionInvokeOptions(body: data)
            )
            if let error = row.error, row.id == nil {
                throw VaultError.paymentFailed(error)
            }
            guard let intent = row.model else {
                throw VaultError.paymentFailed(row.error ?? "Stripe did not return a payment.")
            }
            return intent
        } catch let error as VaultError {
            throw error
        } catch {
            throw VaultError.from(error)
        }
    }
}

private struct ConfirmBody: Encodable {
    let vault_intent_id: UUID
    let apple_pay_token: String
}

/// The function returns either a vault_payment_intents row or `{ "error": "…" }`.
private struct IntentResponse: Decodable {
    let id: UUID?
    let reference_code: String?
    let amount_cents: Int?
    let currency_code: String?
    let status: String?
    let purpose: String?
    let table_invite_code: String?
    let is_demo: Bool?
    let failure_reason: String?
    let error: String?

    var model: DepositIntent? {
        guard
            let id,
            let reference_code,
            let amount_cents,
            let currency_code,
            let status
        else { return nil }

        return DepositIntent(
            id: id,
            referenceCode: reference_code,
            amount: Money(cents: amount_cents),
            currencyCode: currency_code,
            status: DepositIntentStatus(rawValue: status) ?? .failed,
            purpose: DepositPurpose(rawValue: purpose ?? "") ?? .vaultDeposit,
            tableInviteCode: table_invite_code,
            isDemo: is_demo ?? false,
            failureReason: failure_reason ?? error
        )
    }
}
