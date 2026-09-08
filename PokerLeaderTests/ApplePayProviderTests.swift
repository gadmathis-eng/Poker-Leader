import XCTest
@testable import PokerLeader
#if canImport(PassKit)
import PassKit
#endif

@MainActor
final class ApplePayProviderTests: XCTestCase {
    func testMerchantIdentifierMatchesTheEntitlement() {
        XCTAssertEqual(
            ApplePayConfiguration.defaultMerchantIdentifier,
            "merchant.com.mathisgad.pokerleader"
        )
        XCTAssertTrue(ApplePayConfiguration.defaultMerchantIdentifier.hasPrefix("merchant."))
        XCTAssertEqual(ApplePayConfiguration.defaultMerchantCountryCode.count, 2)
    }

    func testSummaryAmountIsMajorUnitsNotCents() {
        XCTAssertEqual(
            ApplePayPaymentRequestFactory.summaryAmount(from: Money(cents: 2_000)),
            NSDecimalNumber(string: "20")
        )
        XCTAssertEqual(
            ApplePayPaymentRequestFactory.summaryAmount(from: Money(cents: 50)),
            NSDecimalNumber(string: "0.5")
        )
    }

    func testMockAuthorisationReturnsADemoToken() async throws {
        var provider = MockApplePayProvider()
        provider.authorizationDelay = .zero
        let result = try await provider.authorize(
            amount: Money(cents: 2_000),
            currencyCode: "USD",
            reference: "PI_TEST",
            summaryLabel: "Pot Master Vault"
        )
        XCTAssertEqual(result.providerToken, "demo_tok_PI_TEST")
        XCTAssertEqual(result.providerName, "mock_apple_pay")
        XCTAssertTrue(result.isDemo)
        XCTAssertFalse(provider.presentsNativeSheet)
        XCTAssertFalse(provider.isLive)
    }

    func testMockCanBeToldToDecline() async {
        var provider = MockApplePayProvider()
        provider.authorizationDelay = .zero
        provider.alwaysDeclines = true
        do {
            _ = try await provider.authorize(
                amount: Money(cents: 1_000),
                currencyCode: "USD",
                reference: "PI_FAIL",
                summaryLabel: "Pot Master Vault"
            )
            XCTFail("Expected a decline")
        } catch {
            XCTAssertEqual(
                VaultError.from(error),
                .paymentFailed("The test card was declined.")
            )
        }
    }

    func testDefaultPaymentProviderIsApplePayAndNotLive() {
        XCTAssertEqual(VaultProviders.payment.backendProviderName, "apple_pay")
        XCTAssertFalse(VaultProviders.payment.isLive)
        XCTAssertTrue(VaultProviders.isSandbox)
        XCTAssertFalse(VaultProviders.applePayCaption.isEmpty)
    }

    #if canImport(PassKit)
    func testPaymentRequestCarriesMerchantAmountAndNetworks() throws {
        let request = try ApplePayPaymentRequestFactory.makeRequest(
            amount: Money(cents: 5_000),
            currencyCode: "gbp",
            summaryLabel: "Pot Master Vault",
            merchantIdentifier: "merchant.com.mathisgad.pokerleader",
            countryCode: "GB"
        )
        XCTAssertEqual(request.merchantIdentifier, "merchant.com.mathisgad.pokerleader")
        XCTAssertEqual(request.countryCode, "GB")
        XCTAssertEqual(request.currencyCode, "GBP")
        XCTAssertEqual(request.paymentSummaryItems.count, 1)
        XCTAssertEqual(request.paymentSummaryItems[0].label, "Pot Master Vault")
        XCTAssertEqual(request.paymentSummaryItems[0].amount, NSDecimalNumber(string: "50"))
        XCTAssertTrue(request.supportedNetworks.contains(.visa))
        XCTAssertTrue(request.supportedNetworks.contains(.masterCard))
        XCTAssertTrue(request.merchantCapabilities.contains(.threeDSecure))
        XCTAssertTrue(request.requiredBillingContactFields.isEmpty)
        XCTAssertTrue(request.requiredShippingContactFields.isEmpty)
    }

    func testPaymentRequestRejectsAZeroAmount() {
        XCTAssertThrowsError(
            try ApplePayPaymentRequestFactory.makeRequest(
                amount: .zero,
                currencyCode: "USD",
                summaryLabel: "Pot Master Vault"
            )
        )
    }
    #endif
}
