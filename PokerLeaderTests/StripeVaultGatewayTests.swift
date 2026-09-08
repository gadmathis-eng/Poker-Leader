import XCTest
@testable import PokerLeader

final class StripeVaultGatewayTests: XCTestCase {
    func testSimulatorAndMockTokensAreNotChargeable() {
        XCTAssertFalse(StripeVaultGateway.isChargeableApplePayToken("demo_tok_PI123"))
        XCTAssertFalse(StripeVaultGateway.isChargeableApplePayToken("pk_tok_Simulated Identifier"))
        XCTAssertFalse(StripeVaultGateway.isChargeableApplePayToken(""))
        XCTAssertFalse(StripeVaultGateway.isChargeableApplePayToken("   "))
    }

    func testPassKitPaymentDataIsTreatedAsChargeable() {
        let paymentData = #"{"version":"EC_v1","data":"abc","signature":"def","header":{}}"#
        let base64 = Data(paymentData.utf8).base64EncodedString()
        XCTAssertTrue(StripeVaultGateway.isChargeableApplePayToken(base64))
        XCTAssertTrue(StripeVaultGateway.isChargeableApplePayToken(paymentData))
    }

    func testStripeIsOffUntilThePlistFlagIsSet() {
        // This test host has no STRIPE_VAULT_ENABLED=YES, so the client must
        // keep using the sandbox confirm rather than calling Stripe.
        XCTAssertFalse(StripeVaultGateway.isEnabled)
    }
}
