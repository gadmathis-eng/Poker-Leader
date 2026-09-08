import Stripe from "https://esm.sh/stripe@17.4.0?target=deno";
import { json, requireEnv, serviceClient, settleVaultIntent } from "../_shared/vault.ts";

/**
 * Stripe-signed webhook. This is the production settle path: the phone is not
 * trusted. `verify_jwt` is off because Stripe calls this, not the player.
 *
 * Secrets: STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, SUPABASE_SERVICE_ROLE_KEY.
 */
Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "POST only" }, 405);
  }

  const signature = request.headers.get("stripe-signature");
  if (!signature) {
    return json({ error: "Missing stripe-signature." }, 400);
  }

  const body = await request.text();

  try {
    const stripe = new Stripe(requireEnv("STRIPE_SECRET_KEY"), {
      apiVersion: "2024-11-20.acacia",
      httpClient: Stripe.createFetchHttpClient(),
    });

    const event = await stripe.webhooks.constructEventAsync(
      body,
      signature,
      requireEnv("STRIPE_WEBHOOK_SECRET"),
    );

    if (
      event.type !== "payment_intent.succeeded" &&
      event.type !== "payment_intent.payment_failed"
    ) {
      return json({ received: true, ignored: event.type });
    }

    const paymentIntent = event.data.object as Stripe.PaymentIntent;
    const vaultIntentId = paymentIntent.metadata?.vault_intent_id;
    if (!vaultIntentId) {
      return json({ received: true, ignored: "no vault_intent_id" });
    }

    const outcome = event.type === "payment_intent.succeeded" ? "succeeded" : "failed";
    const failure = outcome === "failed"
      ? paymentIntent.last_payment_error?.message ?? "Stripe reported a failed payment."
      : null;

    const settled = await settleVaultIntent(
      serviceClient(),
      vaultIntentId,
      outcome,
      event.id,
      failure,
    );
    return json({ received: true, intent: settled.id, status: settled.status });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Webhook failed.";
    return json({ error: message }, 400);
  }
});
