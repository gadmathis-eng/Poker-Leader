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

## 3. Actually charging a card

Connect **Stripe**. Not RevenueCat — that is for a digital subscription, not
the Vault. Step-by-step: [Payments.md](Payments.md).

Short version:

1. Stripe Dashboard → Apple Pay → add `merchant.com.mathisgad.pokerleader` and
   upload the Payment Processing Certificate Stripe generates.
2. Deploy `supabase/functions/stripe-apple-pay` and `stripe-webhook`.
3. `supabase secrets set STRIPE_SECRET_KEY=sk_test_...` and `STRIPE_WEBHOOK_SECRET=whsec_...`.
4. Set `STRIPE_VAULT_ENABLED` to `YES` in `Supabase.plist`.
5. Keep `vault_config.sandbox_mode` on until you have walked a test charge.

No `sk_` key belongs in the app. Face ID still is not a charge until those
functions are live and the plist flag is on.

Real-money poker also needs Apple's real-money gaming entitlement, age gating,
and the geographic restrictions App Review will expect. That is separate from
getting the sheet to open.
