# Making Apple Pay work

The Vault already talks to Apple Pay through `VaultPaymentProvider`. What was
missing was the system sheet. This build opens `PKPaymentAuthorizationController`
on a device that can, and still settles the deposit as demo money until a
payment processor webhook is connected.

Face ID succeeding is not a charge. The card is not billed. `vault_config.sandbox_mode`
is still on, and `ApplePayProvider.isLive` is still false.

## What you will see

| Where you run it | What happens |
|---|---|
| iPhone with Wallet, merchant ID registered | Real Apple Pay sheet. Vault credits **demo funds**. |
| Simulator, or a device that cannot do Apple Pay | Test authorization (the old mock). Caption on Add Money says so. |
| iPhone that *can* do Apple Pay, but the merchant ID is missing | Sheet does not open. The error tells you to register the merchant ID. |

Cash-out is not Apple Pay. Apple Pay only takes payments; it cannot send them.
Payouts still go through the payout provider named on the Cash Out screen.

## 1. Register the merchant ID

1. Open [Apple Developer → Identifiers](https://developer.apple.com/account/resources/identifiers/list).
2. Switch the filter to **Merchant IDs** (or **+** → Merchant IDs).
3. Register **`merchant.com.mathisgad.pokerleader`**.
4. Open App ID **`com.mathisgad.pokerleader`**.
5. Enable **Apple Pay Payment Processing**.
6. Edit it and select `merchant.com.mathisgad.pokerleader`.
7. Save. In Xcode, select your **Team** under Signing & Capabilities and let
   it refresh the provisioning profile.

The same merchant ID is in:

- `PokerLeader/PokerLeader.entitlements`
- `PokerLeader/PokerLeader-Debug.entitlements`
- `PokerLeader/Info.plist` (`ApplePayMerchantIdentifier`)
- `ApplePayConfiguration.defaultMerchantIdentifier`

If you register a different ID, change all four, and set
`ApplePayMerchantCountryCode` in `Info.plist` to the two-letter country on the
merchant agreement (not `EU`).

Xcode error *Provisioning profile doesn't include the Apple Pay merchant IDs*
means this step is not done yet, or the Team in Xcode is not the team that owns
the merchant ID.

## 2. Run it on an iPhone

Simulator usually cannot present Apple Pay. Use a physical iPhone:

1. Add a card in **Wallet**, or use an [Apple Pay sandbox tester](https://developer.apple.com/apple-pay/sandbox-testing/).
2. Build to the device (not Simulator).
3. You → Settings → Vault → Add Money → Confirm with Apple Pay.

The sheet should ask for Face ID / Touch ID. After it closes, the Vault still
shows **Test Mode · Demo Funds**. That is expected.

## 3. Actually charging a card (not done yet)

The sheet returns an encrypted `PKPayment` token. Decrypting and charging it
needs a payment processor (Stripe, Adyen, and similar). Until that webhook
exists, `VaultStore` still calls `vault_sandbox_confirm_deposit`.

To take real money later:

1. Create the merchant in the processor and upload Apple's Payment Processing
   Certificate (the processor's dashboard walks through the CSR).
2. In `didAuthorizePayment`, send the token to your server. The server charges
   it and, on success, calls `vault_settle_deposit_intent` as `service_role`.
3. Complete the Apple Pay sheet with `.success` or `.failure` from that result —
   not before.
4. Set `vault_config.sandbox_mode = false` and `ApplePayProvider.isLive = true`
   only after that path is in place.

No processor secret belongs in the app. See [Vault.md](Vault.md#connecting-a-real-provider).

Real-money poker also needs Apple's real-money gaming entitlement, age gating,
and the geographic restrictions App Review will expect. That is separate from
getting the sheet to open.
