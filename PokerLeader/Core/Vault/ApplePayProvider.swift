import Foundation
#if canImport(PassKit)
import PassKit
#endif

/// Merchant identifiers and country the system Apple Pay sheet is built with.
///
/// The merchant ID has to exist in the Apple Developer account, be attached to
/// App ID `com.mathisgad.pokerleader`, and match the entitlements file. The
/// country is the merchant's, not the player's — it has to be the two-letter
/// ISO code on the merchant agreement. Both can be overridden from Info.plist
/// without a code change; the entitlement still has to list the same merchant.
enum ApplePayConfiguration {
    static let defaultMerchantIdentifier = "merchant.com.mathisgad.pokerleader"
    static let defaultMerchantCountryCode = "US"

    static var merchantIdentifier: String {
        let fromPlist = Bundle.main.object(forInfoDictionaryKey: "ApplePayMerchantIdentifier") as? String
        let trimmed = fromPlist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultMerchantIdentifier : trimmed
    }

    static var merchantCountryCode: String {
        let fromPlist = Bundle.main.object(forInfoDictionaryKey: "ApplePayMerchantCountryCode") as? String
        let trimmed = fromPlist?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        if trimmed.count == 2, trimmed != "EU" { return trimmed }
        return defaultMerchantCountryCode
    }

    static var supportedNetworks: [String] {
        ["visa", "masterCard", "amex", "discover", "maestro"]
    }

    /// True when this hardware can show Apple Pay at all. Simulator usually
    /// cannot; a real iPhone with a Secure Element can, even before a card is
    /// in Wallet.
    static var deviceSupportsApplePay: Bool {
        #if canImport(PassKit)
        PKPaymentAuthorizationController.canMakePayments()
        #else
        false
        #endif
    }
}

/// Builds the `PKPaymentRequest` the system sheet is shown with. Kept free of
/// UI so the amount, merchant and networks can be tested without presenting.
enum ApplePayPaymentRequestFactory {
    static func summaryAmount(from money: Money) -> NSDecimalNumber {
        NSDecimalNumber(decimal: money.decimalValue)
    }

    #if canImport(PassKit)
    static func makeRequest(
        amount: Money,
        currencyCode: String,
        summaryLabel: String,
        merchantIdentifier: String = ApplePayConfiguration.merchantIdentifier,
        countryCode: String = ApplePayConfiguration.merchantCountryCode
    ) throws -> PKPaymentRequest {
        let currency = VaultFX.normalize(currencyCode)
        guard amount.isPositive else {
            throw VaultError.paymentFailed("Apple Pay needs an amount greater than zero.")
        }
        guard currency.count == 3 else {
            throw VaultError.paymentFailed("Apple Pay needs a three-letter currency code.")
        }

        let request = PKPaymentRequest()
        request.merchantIdentifier = merchantIdentifier
        request.countryCode = countryCode
        request.currencyCode = currency
        request.supportedNetworks = supportedNetworks
        request.merchantCapabilities = [.threeDSecure, .debit, .credit]
        request.requiredBillingContactFields = []
        request.requiredShippingContactFields = []
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(
                label: summaryLabel,
                amount: summaryAmount(from: amount),
                type: .final
            )
        ]
        return request
    }

    static var supportedNetworks: [PKPaymentNetwork] {
        var networks: [PKPaymentNetwork] = [.visa, .masterCard, .amex, .discover]
        networks.append(.maestro)
        return networks
    }
    #endif
}

/// Opens the system Apple Pay sheet when the device can, and falls back to the
/// mock only when it cannot — Simulator, an iPad without Wallet, a Mac. A real
/// iPhone that supports Apple Pay but cannot present the sheet (almost always a
/// missing merchant ID) is told that, rather than quietly succeeding.
///
/// Completing the sheet is still not a charge. The token comes back to
/// `VaultStore`, which asks the backend to settle. While sandbox mode is on,
/// that settlement is demo money even after Face ID succeeded.
struct ApplePayProvider: VaultPaymentProvider {
    var displayName: String {
        presentsNativeSheet ? "Apple Pay" : "Apple Pay (Test Mode)"
    }

    var backendProviderName: String { "apple_pay" }
    var isLive: Bool { false }

    var presentsNativeSheet: Bool {
        ApplePayConfiguration.deviceSupportsApplePay
    }

    func isSupported() async -> Bool { true }

    func authorize(
        amount: Money,
        currencyCode: String,
        reference: String,
        summaryLabel: String
    ) async throws -> PaymentAuthorization {
        #if canImport(PassKit)
        if ApplePayConfiguration.deviceSupportsApplePay {
            return try await authorizeWithPassKit(
                amount: amount,
                currencyCode: currencyCode,
                reference: reference,
                summaryLabel: summaryLabel
            )
        }
        #endif
        return try await MockApplePayProvider().authorize(
            amount: amount,
            currencyCode: currencyCode,
            reference: reference,
            summaryLabel: summaryLabel
        )
    }

    #if canImport(PassKit)
    private func authorizeWithPassKit(
        amount: Money,
        currencyCode: String,
        reference: String,
        summaryLabel: String
    ) async throws -> PaymentAuthorization {
        let request = try ApplePayPaymentRequestFactory.makeRequest(
            amount: amount,
            currencyCode: currencyCode,
            summaryLabel: summaryLabel
        )
        let payment = try await ApplePaySheet.shared.authorize(request)
        return PaymentAuthorization(
            providerToken: ApplePaySheet.token(from: payment, reference: reference),
            providerName: backendProviderName,
            isDemo: true
        )
    }
    #endif
}

#if canImport(PassKit)
/// Holds the authorization controller for the life of the sheet. PassKit will
/// not call back if this is released while the sheet is up.
@MainActor
final class ApplePaySheet: NSObject, PKPaymentAuthorizationControllerDelegate {
    static let shared = ApplePaySheet()

    private var controller: PKPaymentAuthorizationController?
    private var continuation: CheckedContinuation<PKPayment, Error>?
    private var authorizedPayment: PKPayment?

    func authorize(_ request: PKPaymentRequest) async throws -> PKPayment {
        if continuation != nil {
            throw VaultError.paymentFailed("Apple Pay is already open.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.authorizedPayment = nil
            let controller = PKPaymentAuthorizationController(paymentRequest: request)
            controller.delegate = self
            self.controller = controller
            controller.present { [weak self] presented in
                guard let self else { return }
                if !presented {
                    self.finish(
                        with: .failure(
                            VaultError.paymentFailed(Self.couldNotPresentMessage)
                        )
                    )
                }
            }
        }
    }

    static var couldNotPresentMessage: String {
        """
        Apple Pay could not open. In Apple Developer create merchant ID \
        \(ApplePayConfiguration.merchantIdentifier), enable Apple Pay on App ID \
        com.mathisgad.pokerleader, select that merchant, then in Xcode set your \
        Team and let it refresh the provisioning profile. Apple Pay has to be \
        tried on an iPhone with Wallet set up — Simulator usually cannot show the sheet.
        """
        .replacingOccurrences(of: "\n", with: " ")
    }

    static func token(from payment: PKPayment, reference: String) -> String {
        let data = payment.token.paymentData
        if data.isEmpty {
            let transaction = payment.token.transactionIdentifier
            if transaction.isEmpty { return "pk_tok_\(reference)" }
            return "pk_tok_\(transaction)"
        }
        return data.base64EncodedString()
    }

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        authorizedPayment = payment
        // Sandbox: accept the token. A live processor would decrypt it and
        // charge before this completion runs, then we would pass .failure if
        // the charge did not go through.
        completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss { [weak self] in
            guard let self else { return }
            if let payment = self.authorizedPayment {
                self.finish(with: .success(payment))
            } else {
                self.finish(with: .failure(VaultError.paymentCanceled))
            }
        }
    }

    private func finish(with result: Result<PKPayment, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        self.controller = nil
        self.authorizedPayment = nil
        continuation.resume(with: result)
    }
}
#endif
