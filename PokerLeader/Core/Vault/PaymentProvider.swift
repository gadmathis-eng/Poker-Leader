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
    /// Whether this provider moves real money. False for everything shipping today.
    var isLive: Bool { get }
    /// Whether the device and account can pay this way at all.
    func isSupported() async -> Bool

    func authorize(
        amount: Money,
        currencyCode: String,
        reference: String,
        summaryLabel: String
    ) async throws -> PaymentAuthorization
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
    var isLive: Bool { false }

    /// Flip to make every authorisation decline, for testing the unhappy path.
    var alwaysDeclines = false

    func isSupported() async -> Bool { true }

    func authorize(
        amount: Money,
        currencyCode: String,
        reference: String,
        summaryLabel: String
    ) async throws -> PaymentAuthorization {
        try await Task.sleep(for: .milliseconds(900))

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
    /// Swapped for the approved provider once one is connected. Until then every
    /// path through the app runs on the mocks, and `isLive` stays false so the
    /// interface can say so.
    static let payment: VaultPaymentProvider = MockApplePayProvider()
    static let payout: VaultPayoutProvider = MockPayoutProvider()

    static var isSandbox: Bool { !payment.isLive || !payout.isLive }
}
