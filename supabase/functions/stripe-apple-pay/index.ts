import Stripe from "https://esm.sh/stripe@17.4.0?target=deno";
import {
  json,
  requireEnv,
  serviceClient,
  settleVaultIntent,
  userClient,
  type VaultIntentRow,
} from "../_shared/vault.ts";

/**
 * Charges a Vault deposit through Stripe using the Apple Pay token PassKit
 * already collected. The amount comes from vault_payment_intents, never from
 * the phone.
 *
 * Secrets: STRIPE_SECRET_KEY, SUPABASE_URL, SUPABASE_ANON_KEY,
 * SUPABASE_SERVICE_ROLE_KEY (provided by Supabase).
 */
Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "POST only" }, 405);
  }

  const auth = request.headers.get("Authorization");
  if (!auth?.startsWith("Bearer ")) {
    return json({ error: "Sign in to pay." }, 401);
  }

  let payload: { vault_intent_id?: string; apple_pay_token?: string };
  try {
    payload = await request.json();
  } catch {
    return json({ error: "Expected JSON." }, 400);
  }

  const intentId = payload.vault_intent_id?.trim();
  const applePayToken = payload.apple_pay_token?.trim();
  if (!intentId || !applePayToken) {
    return json({ error: "vault_intent_id and apple_pay_token are required." }, 400);
  }
  if (applePayToken.startsWith("demo_tok_") || applePayToken.startsWith("pk_tok_")) {
    return json({
      error: "That Apple Pay token is a simulator stand-in. Stripe will not charge it. Run on an iPhone with Wallet.",
    }, 400);
  }

  try {
    const user = userClient(auth);
    const { data: intent, error: intentError } = await user
      .from("vault_payment_intents")
      .select(
        "id, user_id, reference_code, amount_cents, currency_code, status, purpose, table_invite_code, is_demo, failure_reason",
      )
      .eq("id", intentId)
      .maybeSingle();

    if (intentError) return json({ error: intentError.message }, 400);
    if (!intent) return json({ error: "Unknown payment." }, 404);

    const row = intent as VaultIntentRow;
    if (row.status !== "requires_confirmation") {
      return json(row);
    }

    const stripe = new Stripe(requireEnv("STRIPE_SECRET_KEY"), {
      apiVersion: "2024-11-20.acacia",
      httpClient: Stripe.createFetchHttpClient(),
    });

    const pkToken = decodeApplePayToken(applePayToken);
    const stripeToken = await stripe.tokens.create({ pk_token: pkToken });

    const paymentIntent = await stripe.paymentIntents.create({
      amount: row.amount_cents,
      currency: row.currency_code.toLowerCase(),
      confirm: true,
      confirmation_method: "automatic",
      payment_method_data: {
        type: "card",
        card: { token: stripeToken.id },
      },
      metadata: {
        vault_intent_id: row.id,
        vault_reference: row.reference_code,
      },
    }, {
      idempotencyKey: `vault:${row.id}`,
    });

    const admin = serviceClient();
    await admin
      .from("vault_payment_intents")
      .update({
        provider: "stripe",
        provider_intent_id: paymentIntent.id,
      })
      .eq("id", row.id);

    if (paymentIntent.status === "succeeded") {
      const settled = await settleVaultIntent(
        admin,
        row.id,
        "succeeded",
        paymentIntent.id,
      );
      return json(settled);
    }

    if (paymentIntent.status === "requires_action") {
      return json({
        error: "Stripe asked for extra authentication. Apple Pay should not need that for this charge.",
        stripe_status: paymentIntent.status,
      }, 402);
    }

    const settled = await settleVaultIntent(
      admin,
      row.id,
      "failed",
      paymentIntent.id,
      `Stripe status ${paymentIntent.status}`,
    );
    return json(settled, 402);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Stripe could not charge this payment.";
    return json({ error: message }, 500);
  }
});

function decodeApplePayToken(raw: string): string {
  const trimmed = raw.trim();
  if (trimmed.startsWith("{")) return trimmed;
  try {
    const decoded = atob(trimmed);
    if (decoded.startsWith("{")) return decoded;
  } catch {
    // Not base64. Pass through and let Stripe reject it.
  }
  return trimmed;
}
