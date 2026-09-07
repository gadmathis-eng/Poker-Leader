-- The Vault is one wallet. vault_summary used to hardcode USD. Player
-- available / pending accounts are looked up without currency, so in-play
-- chips on a GBP table are still that same pot — tagged with the table's
-- settlement unit, not a second wallet. Report the available wallet's
-- currency and keep summing the player's own accounts.

create or replace function public.vault_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    uid uuid := public.vault_require_user();
    wallet_currency text;
    available bigint;
    in_play bigint;
    pending_withdrawal bigint;
    pending_deposit bigint;
    profile public.vault_compliance_profiles;
    config public.vault_config;
begin
    select currency_code into wallet_currency
    from public.vault_accounts
    where owner_user_id = uid and kind = 'available'
    order by created_at
    limit 1;

    wallet_currency := coalesce(wallet_currency, 'USD');

    select coalesce(sum(balance_cents) filter (where kind = 'available'), 0),
           coalesce(sum(balance_cents) filter (where kind = 'in_play'), 0),
           coalesce(sum(balance_cents) filter (where kind = 'pending_withdrawal'), 0)
    into available, in_play, pending_withdrawal
    from public.vault_accounts
    where owner_user_id = uid;

    select coalesce(sum(amount_cents), 0) into pending_deposit
    from public.vault_payment_intents
    where user_id = uid
      and purpose = 'vault_deposit'
      and status in ('requires_confirmation', 'processing');

    select * into profile from public.vault_compliance_profiles where user_id = uid;
    select * into config from public.vault_config where id;

    return jsonb_build_object(
        'currency_code', wallet_currency,
        'available_cents', available,
        'in_play_cents', in_play,
        'pending_deposit_cents', pending_deposit,
        'pending_withdrawal_cents', pending_withdrawal,
        'total_cents', available + in_play + pending_deposit + pending_withdrawal,
        'withdrawable_cents', available,
        'is_sandbox', public.vault_is_sandbox(),
        'deposit_min_cents', config.deposit_min_cents,
        'deposit_max_cents', config.deposit_max_cents,
        'withdrawal_min_cents', config.withdrawal_min_cents,
        'withdrawal_fee_flat_cents', config.withdrawal_fee_flat_cents,
        'withdrawal_fee_basis_points', config.withdrawal_fee_basis_points,
        'identity_status', coalesce(profile.identity_status, 'unverified'),
        'payout_method_status', coalesce(profile.payout_method_status, 'none'),
        'account_status', coalesce(profile.account_status, 'active'),
        'jurisdiction_status', coalesce(profile.jurisdiction_status, 'sandbox'),
        'self_excluded_until', profile.self_excluded_until
    );
end;
$$;
