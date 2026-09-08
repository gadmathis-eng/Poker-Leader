import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";

export function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`${name} is not set`);
  }
  return value;
}

export function serviceClient(): SupabaseClient {
  return createClient(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

export function userClient(authHeader: string): SupabaseClient {
  return createClient(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_ANON_KEY"),
    {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    },
  );
}

export type VaultIntentRow = {
  id: string;
  user_id: string;
  reference_code: string;
  amount_cents: number;
  currency_code: string;
  status: string;
  purpose: string;
  table_invite_code: string | null;
  is_demo: boolean;
  failure_reason: string | null;
};

export async function settleVaultIntent(
  admin: SupabaseClient,
  intentId: string,
  outcome: "succeeded" | "failed" | "canceled",
  providerEventId: string,
  failureReason: string | null = null,
): Promise<VaultIntentRow> {
  const { data, error } = await admin.rpc("vault_settle_deposit_intent", {
    p_intent_id: intentId,
    p_outcome: outcome,
    p_provider_event_id: providerEventId,
    p_failure_reason: failureReason,
  });
  if (error) {
    throw new Error(error.message);
  }
  return data as VaultIntentRow;
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
