# Stripe Edge Functions

These two functions are the server half of Vault deposits. See
[Docs/Payments.md](../../Docs/Payments.md).

| Function | Who calls it | JWT |
|---|---|---|
| `stripe-apple-pay` | the iOS app, after Apple Pay | signed-in player |
| `stripe-webhook` | Stripe | off — Stripe signature instead |

```bash
supabase secrets set STRIPE_SECRET_KEY=sk_test_...
supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_...
supabase functions deploy stripe-apple-pay
supabase functions deploy stripe-webhook
```

Then set `STRIPE_VAULT_ENABLED` to `YES` in `PokerLeader/Supabase.plist`.
Do not put `sk_` or `whsec_` keys in the app.
