import Foundation

/// The seam an approved payment provider is connected through later.
///
/// What a provider returns is an *authorisation*: the player agreed to pay. It
/// is not money. Money appears only when the backend has settled the matching
/// deposit intent, which it does from the provider's signed webhook and never
/// on the say-so of this app. That is why `authorize` hands back a token to pass
/// along rather than a balance to add.
///
/// Nothing here touches card numbers or Apple Pay credentials, and no provider
/// secret key belongs in the app: the publishable identifiers a real
/// integration needs are configuration, and the private keys stay on the server.
protocol VaultPaymentProvider: Sendable {
    var displayName: String { get }
    /// Written onto the deposit intent so the backend knows which rail authorised it.
    var backendProviderName: String { get }
    /// Whether this provider moves real money. False for everything shipping today.
    var isLive: Bool { get }
    /// True when `authorize` will open the system Apple Pay sheet rather than the mock.
    var presentsNativeSheet: Bool { get }
    /// Whether the device and account can pay this way at all.
    func isSupported() async -> Bool

    func authorize(
        amount: Money,
        currencyCode: String,
        reference: String,
        summaryLabel: String
    ) async throws -> PaymentAuthorization
}

extension VaultPaymentProvider {
    var presentsNativeSheet: Bool { false }
}

struct PaymentAuthorization: Sendable {
    /// What the backend quotes to the provider to settle the payment. It is not
    /// a receipt and it is not proof of anything on its own.
    let providerToken: String
    let providerName: String
    let isDemo: Bool
}

/// The payout side. Apple Pay is a way to *take* a payment, not a way to send
/// one, so cash-outs are never described to the player as going out through
/// Apple Pay — they go to whichever payout provider the operator has approved
/// and the player has verified.
protocol VaultPayoutProvider: Sendable {
    var displayName: String { get }
    var isLive: Bool { get }
    /// How the money reaches the player, in the words shown on the Cash Out
    /// screen. Must describe what the provider actually supports.
    var destinationDescription: String { get }
}

// MARK: - Sandbox implementations

/// Stands in for Apple Pay while the build is in sandbox. It shows the pause a
/// real sheet has and can be told to decline, so the failure path is exercised
/// as often as the happy one — but it authorises nothing, charges nothing, and
/// the token it returns is only good against the sandbox backend.
struct MockApplePayProvider: VaultPaymentProvider {
    var displayName: String { "Apple Pay (Test Mode)" }
    var backendProviderName: String { "mock_apple_pay" }
    var isLive: Bool { false }

    /// Flip to make every authorisation decline, for testing the unhappy path.
    var alwaysDeclines = false
    var authorizationDelay: Duration = .milliseconds(900)

    func isSupported() async -> Bool { true }

    func authorize(
        amount: Money,
        currencyCode: String,
        reference: String,
        summaryLabel: String
    ) async throws -> PaymentAuthorization {
        if authorizationDelay != .zero {
            try await Task.sleep(for: authorizationDelay)
        }

        if alwaysDeclines {
            throw VaultError.paymentFailed("The test card was declined.")
        }

        return PaymentAuthorization(
            providerToken: "demo_tok_\(reference)",
            providerName: "mock_apple_pay",
            isDemo: true
        )
    }
}

/// Stands in for the payout rail. Named as a bank transfer rather than Apple
/// Pay because that is what a payout provider can actually do.
struct MockPayoutProvider: VaultPayoutProvider {
    var displayName: String { "Test payout provider" }
    var isLive: Bool { false }
    var destinationDescription: String {
        "your verified bank account"
    }
}

enum VaultProviders {
    /// Opens the system Apple Pay sheet on a device that can. Simulator and
    /// anything without Wallet fall back to the mock so the rest of the Vault
    /// can still be walked through. `isLive` stays false until a processor
    /// webhook is connected and sandbox mode is turned off — Face ID is not a charge.
    static let payment: VaultPaymentProvider = ApplePayProvider()
    static let payout: VaultPayoutProvider = MockPayoutProvider()

    static var isSandbox: Bool { !payment.isLive || !payout.isLive }

    /// Why the Add Money / buy-in button will or will not open Apple Pay.
    static var applePayCaption: String {
        if StripeVaultGateway.isEnabled {
            return "Apple Pay is charged through Stripe. The Vault is credited only after Stripe confirms the payment — never because this app said so."
        }
        if payment.presentsNativeSheet {
            return "Apple Pay will open on this device. The Vault still only credits demo funds until Stripe is connected — Face ID is not a charge."
        }
        return "Apple Pay cannot open on this device (Simulator usually cannot). A test authorization is used instead. To see the real sheet: register merchant ID \(ApplePayConfiguration.merchantIdentifier) in Apple Developer, enable Apple Pay on the App ID, and run on an iPhone with Wallet set up. To actually charge a card, connect Stripe (Docs/Payments.md)."
    }
}
