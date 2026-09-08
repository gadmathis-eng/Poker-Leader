# Stripe and RevenueCat

They do **different jobs**. You can use both in the same app. You cannot use
them as substitutes for each other.

| Job | Use | Do not use |
|---|---|---|
| Put money in the Vault (Apple Pay, cards) | **Stripe** | RevenueCat |
| Pay that money back out (cash-out) | **Stripe** (Connect / payouts) | Apple Pay, RevenueCat |
| Sell a digital subscription (Pot Master Pro, extra themes, cloud extras) | **RevenueCat** + StoreKit | Stripe in the iOS app |

Apple’s rule is the reason for the split. Unlocking digital features inside an
iOS app has to go through In-App Purchase. Adding spendable, withdrawable
balance to a wallet must **not** go through In-App Purchase. RevenueCat is a
StoreKit wrapper. The Vault is a wallet. Putting Vault deposits through
RevenueCat would both fail App Review and credit money the ledger must not
trust.

The current Apple Pay sheet is PassKit. Stripe is what **charges** the token.
RevenueCat is unused today because this app has no paid digital product.

---

## Stripe — Vault deposits and Apple Pay

This is the path that makes Add Money charge a card.

The app already opens Apple Pay and opens a `vault_payment_intents` row. Stripe
sits between those two steps and `vault_settle_deposit_intent`. The amount
charged is always the amount stored on that row. The client never gets to name
a different figure.

```
Add Money
  → vault_create_deposit_intent   (amount lives here)
  → Apple Pay sheet               (PassKit, already built)
  → stripe-apple-pay function     (charges that amount)
  → vault_settle_deposit_intent   (credits the Vault)
  → stripe-webhook                (same settle, if the first call dropped)
```

### 1. Stripe Dashboard

1. Create a [Stripe](https://dashboard.stripe.com) account. Start in **Test mode**.
2. Developers → API keys. Copy the **secret key** (`sk_test_…`). It stays on
   the server. It never goes in the app.
3. Settings → Payment methods → **Apple Pay**.
4. Add merchant ID `merchant.com.mathisgad.pokerleader`.
5. Stripe gives you a CSR. In Apple Developer create a **Payment Processing
   Certificate** from that CSR, download the `.cer`, upload it to Stripe.
6. Developers → Webhooks → Add endpoint:
   `https://<project-ref>.supabase.co/functions/v1/stripe-webhook`
   Events: `payment_intent.succeeded`, `payment_intent.payment_failed`.
   Copy the signing secret (`whsec_…`).

In-app Apple Pay does **not** need Apple’s web domain association file. That
file is only for Apple Pay on the web.

### 2. Supabase secrets and deploy

```bash
supabase secrets set STRIPE_SECRET_KEY=sk_test_...
supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_...
supabase functions deploy stripe-apple-pay
supabase functions deploy stripe-webhook
```

`stripe-webhook` verifies Stripe’s signature and must be called **without** a
user JWT (`verify_jwt = false` in `supabase/config.toml`). `stripe-apple-pay`
requires the signed-in player’s JWT.

Turn the client onto this path in `PokerLeader/Supabase.plist`:

```xml
<key>STRIPE_VAULT_ENABLED</key>
<string>YES</string>
```

Leave it off (or omit it) until the functions are deployed. While it is off,
the Vault still settles through `vault_sandbox_confirm_deposit` and nothing is
charged.

### 3. Go live later

1. Walk a Test-mode deposit on a device with Apple Pay.
2. Confirm the Stripe Dashboard shows a PaymentIntent for the **intent’s**
   cents, not a number the phone made up.
3. Confirm the Vault balance matches that PaymentIntent.
4. Switch Stripe to live keys, redeploy secrets, register a live webhook.
5. `update vault_config set sandbox_mode = false;`
6. Real-money poker still needs Apple’s gaming entitlement, age gating, and
   legal review. Turning Stripe on does not finish that.

Cash-out: implement `VaultPayoutProvider` against Stripe Connect (Express or
Custom accounts, or a payouts-only integration). Apple Pay cannot send money.
RevenueCat cannot send money.

Code that does this:

- Client: `PokerLeader/Core/Vault/StripeVaultGateway.swift`
- Charge: `supabase/functions/stripe-apple-pay`
- Webhook: `supabase/functions/stripe-webhook`

---

## RevenueCat — digital subscriptions only

Use RevenueCat if you want to sell something that lives **in the app**: a Pro
subscription, extra felt themes, removing a banner. Do not use it to add
balance to the Vault, to buy chips, or to cash out.

RevenueCat’s Stripe connection is for **web subscriptions** billed by Stripe.
It is still a subscription, not a wallet top-up.

### If you add a Pro subscription later

1. App Store Connect → Paid Apps agreement, then a subscription product
   (for example `potmaster_pro_monthly`).
2. [RevenueCat](https://www.revenuecat.com) → add iOS app with bundle ID
   `com.mathisgad.pokerleader`.
3. Add that StoreKit product, an entitlement (`pro`), and an offering.
4. Xcode → SPM → `https://github.com/RevenueCat/purchases-ios`.
5. `Purchases.configure(withAPIKey: "appl_…")` using the **public** SDK key.
6. Gate the extra UI on `customerInfo.entitlements["pro"]?.isActive`.
7. Keep Vault deposits on Stripe. A RevenueCat purchase must never call
   `vault_create_deposit_intent` or `vault_settle_deposit_intent`.

There is no RevenueCat product in this app today, so the SDK is not linked.

---

## Why not both on the same payment

A player tapping **Add Money** must hit one rail:

- Stripe + Apple Pay → money that can sit in the Vault and later leave it.
- RevenueCat + StoreKit → a digital entitlement that never becomes cash.

Mixing them (IAP that credits the Vault, or Stripe that unlocks app features on
iOS) is how App Review rejects the binary. The ledger already assumes the
first rail. Leave the second rail out until there is a real Pro feature to sell.
