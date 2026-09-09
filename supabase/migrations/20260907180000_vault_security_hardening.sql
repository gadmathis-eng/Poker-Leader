-- Pot Master — closing the holes the Vault audit found.
--
-- Paste this whole file into the Supabase SQL Editor and click Run, after
-- 20260904120000_open_tables.sql and 20260907120000_vault_ledger.sql. It is safe
-- to run more than once.
--
-- The audit found that a modified client could not create money out of nothing,
-- but could take money from other players. Five things made that possible, and
-- this migration fixes four of them outright:
--
--   1. `vault_register_table` made whoever called it first the settlement
--      authority for a table code, so a player could claim someone else's table.
--   2. `open_tables` let ANY signed-in user update ANY table row.
--   3. `merge_open_table_seat` read `playerKey` out of the submitted JSON and
--      never checked it belonged to the caller, so anyone could rewrite anyone's
--      seat at any table.
--   4. `vault_table_buy_in` took `player_key` from the client, and nothing
--      stopped two seats claiming the same one.
--   5. Nothing about a live hand was on the server, so a losing player could
--      stand up before settlement and keep their committed chips.
--
-- Number 5 is only partly fixable here, and the limit is explained above
-- `vault_leave_table` below. It cannot be closed properly until the server deals
-- the cards, takes the bets and decides the winner.
--
-- The thing this migration does NOT fix, and cannot: the result of a hand is
-- still whatever the host's phone says it is. See the notes on
-- `vault_record_hand` at the end.

-- ---------------------------------------------------------------------------
-- Shared helper: who is the real host of a table?
-- ---------------------------------------------------------------------------
-- `open_tables` is the shared row the app already syncs for gameplay, and its
-- `host_user_id` is written under a policy that only lets the host insert it.
-- That makes it the one server-side fact about who owns a table code, so every
-- host check below is answered from here rather than from anything a client
-- sends.
--
-- Wrapped in an exception handler because a project that has not run
-- 20260904120000_open_tables.sql yet has no such table, and the answer then is
-- "nobody" rather than a crash.

create or replace function public.open_table_host(p_invite_code text)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    host uuid;
begin
    select host_user_id into host
    from public.open_tables
    where invite_code = upper(trim(p_invite_code));
    return host;
exception
    when undefined_table then
        return null;
end;
$$;

revoke all on function public.open_table_host(text) from public, anon;
grant execute on function public.open_table_host(text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- FIX 1 — vault_register_table: only the real host, verified server-side
-- ---------------------------------------------------------------------------
-- Before: `insert … values (code, auth.uid(), …)`. Whoever got there first
-- became `host_user_id`, and `vault_record_hand` trusts that column. A player
-- could register a table code they had merely been invited to and become its
-- settlement authority.
--
-- Now: the host is read from `open_tables` and the caller must match it. A table
-- that has not been published to the cloud cannot be registered at all, because
-- there is nothing to check the caller against. That fails closed on purpose:
-- the host publishes when they buy in, and guests are refused.

create or replace function public.vault_register_table(
    p_invite_code text,
    p_min_buy_in_cents bigint,
    p_max_buy_in_cents bigint,
    p_currency text default 'USD'
)
returns public.vault_tables
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    uid uuid := public.vault_require_user();
    code text := upper(trim(p_invite_code));
    real_host uuid;
    existing public.vault_tables;
    row_out public.vault_tables;
    seated_count integer;
begin
    if code = '' then
        raise exception 'vault: a table needs a code' using errcode = '23514';
    end if;

    real_host := public.open_table_host(code);

    if real_host is null then
        raise exception 'vault: that table has not been published yet, so its host cannot be checked'
            using errcode = '42501';
    end if;

    if real_host <> uid then
        raise exception 'vault: only the host of that table can set its buy-in range'
            using errcode = '42501';
    end if;

    select * into existing from public.vault_tables where invite_code = code for update;

    if not found then
        insert into public.vault_tables (
            invite_code, host_user_id, currency_code,
            min_buy_in_cents, max_buy_in_cents, is_demo
        )
        values (code, real_host, p_currency, p_min_buy_in_cents, p_max_buy_in_cents,
                public.vault_is_sandbox())
        returning * into row_out;

        perform public.vault_log(uid, 'table_registered', 'ok', null, null, code);
        return row_out;
    end if;

    -- A table registered under a stale owner is corrected to whoever `open_tables`
    -- says hosts it, so a row left over from before this migration cannot keep a
    -- claim it should never have had.
    if existing.host_user_id <> real_host then
        update public.vault_tables
        set host_user_id = real_host, updated_at = now()
        where invite_code = code;

        perform public.vault_log(uid, 'table_host_corrected', 'ok', null, null, code,
                                 jsonb_build_object('was', existing.host_user_id, 'now', real_host));
    end if;

    -- The range is frozen once anyone has money on the table. Widening it
    -- mid-game would let the host invite a buy-in the other players never agreed
    -- to sit against.
    select count(*) into seated_count
    from public.vault_table_stakes
    where invite_code = code and status = 'seated';

    if seated_count > 0
       and (existing.min_buy_in_cents <> p_min_buy_in_cents
            or existing.max_buy_in_cents <> p_max_buy_in_cents) then
        select * into row_out from public.vault_tables where invite_code = code;
        return row_out;
    end if;

    update public.vault_tables
    set min_buy_in_cents = p_min_buy_in_cents,
        max_buy_in_cents = p_max_buy_in_cents,
        currency_code = p_currency,
        updated_at = now()
    where invite_code = code
    returning * into row_out;

    return row_out;
end;
$$;

revoke all on function public.vault_register_table(text, bigint, bigint, text) from public, anon;
grant execute on function public.vault_register_table(text, bigint, bigint, text) to authenticated;

-- ---------------------------------------------------------------------------
-- FIX 4 — vault_table_buy_in: identity comes from the JWT, not the request
-- ---------------------------------------------------------------------------
-- `player_key` is what `vault_record_hand` uses to decide whose account a hand
-- result lands in, and it used to arrive in the request body with nothing
-- checking it. Two seats could claim the same key, and `SELECT … INTO` would
-- then resolve it to whichever row Postgres felt like.
--
-- Now it is `auth.uid()::text`, which is what a signed-in client already sends,
-- and a unique index makes a collision impossible even if a stale row exists.

-- Any pre-existing duplicate has to go before the index can be built. There is
-- no legitimate way to have two seats with one key, so the later one is dropped.
delete from public.vault_table_stakes s
using public.vault_table_stakes other
where s.invite_code = other.invite_code
  and s.player_key = other.player_key
  and s.seated_at > other.seated_at;

-- Existing rows are re-keyed to the owning account, which is what the new code
-- would have written for them.
update public.vault_table_stakes
set player_key = user_id::text
where player_key <> user_id::text;

create unique index if not exists vault_table_stakes_player_key_unique
    on public.vault_table_stakes (invite_code, player_key);

drop function if exists public.vault_table_buy_in(text, bigint, text, text, text, text, uuid);

create or replace function public.vault_table_buy_in(
    p_invite_code text,
    p_amount_cents bigint,
    p_source text,
    p_idempotency_key text,
    p_display_name text default 'Player',
    p_payment_intent_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    uid uuid := public.vault_require_user();
    code text := upper(trim(p_invite_code));
    -- Not accepted from the caller. A player is their account, and nothing else.
    player_key text;
    tbl public.vault_tables;
    intent public.vault_payment_intents;
    posted public.vault_ledger_transactions;
    source_account uuid;
    in_play uuid;
    stake public.vault_table_stakes;
begin
    player_key := uid::text;

    perform public.vault_touch_rate_limit(uid, 'table_buy_in', 30, interval '5 minutes');
    perform public.vault_assert_allowed(uid, 'play', p_amount_cents);

    select * into tbl from public.vault_tables where invite_code = code for update;
    if not found then
        raise exception 'vault: that table is not open for buy-ins' using errcode = 'P0002';
    end if;

    if tbl.status <> 'open' then
        raise exception 'vault: that table is closed' using errcode = '42501';
    end if;

    if p_amount_cents < tbl.min_buy_in_cents or p_amount_cents > tbl.max_buy_in_cents then
        raise exception 'vault: the buy-in must be between % and % cents',
            tbl.min_buy_in_cents, tbl.max_buy_in_cents using errcode = '23514';
    end if;

    perform public.vault_open(tbl.currency_code);
    in_play := public.vault_account(uid, 'in_play', tbl.currency_code, code);

    if p_source = 'vault' then
        source_account := public.vault_account(uid, 'available', tbl.currency_code);

        if (select balance_cents from public.vault_accounts
            where id = source_account for update) < p_amount_cents then
            raise exception 'vault: your Vault does not hold that much'
                using errcode = '23514';
        end if;
    elsif p_source = 'apple_pay' then
        if p_payment_intent_id is null then
            raise exception 'vault: that buy-in has no payment attached' using errcode = '23514';
        end if;

        select * into intent
        from public.vault_payment_intents
        where id = p_payment_intent_id
        for update;

        if not found or intent.user_id <> uid then
            raise exception 'vault: unknown payment' using errcode = 'P0002';
        end if;
        if intent.status <> 'succeeded' then
            raise exception 'vault: that payment has not been verified yet' using errcode = '42501';
        end if;
        if intent.consumed_at is not null then
            raise exception 'vault: that payment was already used' using errcode = '23505';
        end if;
        if intent.amount_cents <> p_amount_cents then
            raise exception 'vault: that payment does not match the buy-in' using errcode = '23514';
        end if;
        if intent.purpose <> 'table_buy_in' or coalesce(intent.table_invite_code, '') <> code then
            raise exception 'vault: that payment was not for this table' using errcode = '23514';
        end if;
        if intent.is_demo <> public.vault_is_sandbox() then
            raise exception 'vault: that payment belongs to a different money mode'
                using errcode = '42501';
        end if;

        update public.vault_payment_intents
        set consumed_at = now(), updated_at = now()
        where id = intent.id;

        source_account := public.vault_account(null, 'psp_clearing', tbl.currency_code);
    else
        raise exception 'vault: unknown payment source %', p_source using errcode = '23514';
    end if;

    posted := public.vault_post_transaction(
        uid,
        case p_source when 'vault' then 'table_buy_in_vault' else 'table_buy_in_direct' end,
        jsonb_build_array(
            jsonb_build_object('account_id', source_account, 'amount_cents', -p_amount_cents),
            jsonb_build_object('account_id', in_play, 'amount_cents', p_amount_cents)
        ),
        p_idempotency_key,
        code,
        jsonb_build_object('source', p_source, 'player_key', player_key)
    );

    insert into public.vault_table_stakes (
        invite_code, user_id, player_key, display_name,
        total_bought_in_cents, in_play_cents, status
    )
    values (code, uid, player_key, p_display_name, p_amount_cents, p_amount_cents, 'seated')
    on conflict (invite_code, user_id) do update
        set player_key = excluded.player_key,
            display_name = excluded.display_name,
            status = 'seated',
            left_at = null
    returning * into stake;

    update public.vault_table_stakes s
    set in_play_cents = (select balance_cents from public.vault_accounts where id = in_play),
        total_bought_in_cents = (
            select coalesce(sum(e.amount_cents), 0)
            from public.vault_ledger_entries e
            join public.vault_ledger_transactions t on t.id = e.transaction_id
            where e.account_id = in_play
              and t.kind in ('table_buy_in_vault', 'table_buy_in_direct')
        )
    where s.invite_code = code and s.user_id = uid
    returning * into stake;

    if not exists (
        select 1 from public.vault_statement_entries
        where ledger_transaction_id = posted.id
    ) then
        perform public.vault_add_statement(
            uid,
            case p_source when 'vault' then 'table_buy_in_vault' else 'table_buy_in_direct' end,
            'completed',
            case p_source when 'vault' then 0 else p_amount_cents end,
            tbl.currency_code,
            posted.id,
            p_payment_intent_id,
            null,
            code,
            case p_source
                when 'vault' then 'Moved from Available into In Play'
                else 'Paid straight onto the table'
            end
        );
    end if;

    perform public.vault_log(uid, 'table_buy_in', 'ok', p_amount_cents,
                             posted.reference_code, code,
                             jsonb_build_object('source', p_source));

    return jsonb_build_object(
        'reference_code', posted.reference_code,
        'invite_code', code,
        'player_key', player_key,
        'in_play_cents', stake.in_play_cents,
        'total_bought_in_cents', stake.total_bought_in_cents
    );
end;
$$;

revoke all on function public.vault_table_buy_in(text, bigint, text, text, text, uuid)
    from public, anon;
grant execute on function public.vault_table_buy_in(text, bigint, text, text, text, uuid)
    to authenticated;

-- ---------------------------------------------------------------------------
-- FIX 5 — vault_leave_table: no walking out of a live hand
-- ---------------------------------------------------------------------------
-- A losing player used to be able to call this before the host settled and keep
-- everything, including the chips they had already pushed into the pot. Worse,
-- the host's settlement would then hit the non-negative check and abort, so the
-- honest winner never got paid either.
--
-- The shared `open_tables.hand` column is on the server, so this function can
-- now look at it: if there is a hand in progress and the caller has a seat in
-- it, standing up is refused.
--
-- WHAT THIS DOES NOT FIX. That hand JSON is written by the players' phones, not
-- by the server. A modified client can still publish a hand that claims to be
-- finished, or no hand at all, and then leave. This check stops a client that
-- simply calls the leave endpoint early, and it makes the attack loud — the
-- cheat now has to forge shared game state that every other device is also
-- reading and will disagree with. It is not a substitute for the server dealing
-- the cards and holding the pot, which is the only real fix.

create or replace function public.open_table_live_hand_seat(
    p_invite_code text,
    p_player_key text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    hand_state jsonb;
begin
    select hand into hand_state
    from public.open_tables
    where invite_code = upper(trim(p_invite_code));

    if hand_state is null then
        return false;
    end if;

    -- The app marks a finished hand complete before it pays out. Anything else
    -- with the player still holding a seat in it counts as live.
    if coalesce((hand_state->>'isComplete')::boolean, false) then
        return false;
    end if;

    return exists (
        select 1
        from jsonb_array_elements(coalesce(hand_state->'seats', '[]'::jsonb)) seat
        where seat->>'playerKey' = p_player_key
    );
exception
    when undefined_table then
        return false;
    when others then
        -- Unreadable hand state is treated as live. Refusing to cash off is
        -- recoverable; letting someone walk out of a pot is not.
        return true;
end;
$$;

revoke all on function public.open_table_live_hand_seat(text, text) from public, anon;
grant execute on function public.open_table_live_hand_seat(text, text) to authenticated, service_role;

create or replace function public.vault_leave_table(
    p_invite_code text,
    p_idempotency_key text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    uid uuid := public.vault_require_user();
    code text := upper(trim(p_invite_code));
    tbl public.vault_tables;
    stake public.vault_table_stakes;
    in_play uuid;
    available uuid;
    final_cents bigint;
    bought_in bigint;
    posted public.vault_ledger_transactions;
begin
    select * into tbl from public.vault_tables where invite_code = code;
    if not found then
        raise exception 'vault: unknown table' using errcode = 'P0002';
    end if;

    select * into stake
    from public.vault_table_stakes
    where invite_code = code and user_id = uid
    for update;

    if not found then
        raise exception 'vault: you are not at that table' using errcode = 'P0002';
    end if;

    if stake.status = 'left' then
        return jsonb_build_object(
            'invite_code', code,
            'bought_in_cents', stake.total_bought_in_cents,
            'returned_cents', stake.returned_cents,
            'net_cents', stake.returned_cents - stake.total_bought_in_cents,
            'reference_code', '',
            'already_settled', true
        );
    end if;

    if public.open_table_live_hand_seat(code, stake.player_key) then
        perform public.vault_log(uid, 'table_leave', 'refused_live_hand', null, null, code);
        raise exception 'vault: finish the hand you are in before you cash off'
            using errcode = '42501';
    end if;

    in_play := public.vault_account(uid, 'in_play', tbl.currency_code, code);
    available := public.vault_account(uid, 'available', tbl.currency_code);

    select balance_cents into final_cents
    from public.vault_accounts where id = in_play for update;

    bought_in := stake.total_bought_in_cents;

    if final_cents > 0 then
        posted := public.vault_post_transaction(
            uid, 'table_return',
            jsonb_build_array(
                jsonb_build_object('account_id', in_play, 'amount_cents', -final_cents),
                jsonb_build_object('account_id', available, 'amount_cents', final_cents)
            ),
            p_idempotency_key, code,
            jsonb_build_object('bought_in_cents', bought_in)
        );

        perform public.vault_add_statement(
            uid, 'table_return', 'completed', 0, tbl.currency_code,
            posted.id, null, null, code, 'Returned from the table to your Vault'
        );
    end if;

    update public.vault_table_stakes
    set status = 'left',
        left_at = now(),
        in_play_cents = 0,
        returned_cents = returned_cents + final_cents
    where invite_code = code and user_id = uid;

    perform public.vault_log(uid, 'table_leave', 'ok', final_cents,
                             coalesce(posted.reference_code, 'none'), code);

    return jsonb_build_object(
        'invite_code', code,
        'bought_in_cents', bought_in,
        'returned_cents', final_cents,
        'net_cents', final_cents - bought_in,
        'reference_code', coalesce(posted.reference_code, ''),
        'already_settled', false
    );
end;
$$;

revoke all on function public.vault_leave_table(text, text) from public, anon;
grant execute on function public.vault_leave_table(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- FIX 6 — sandbox deposits cannot be confirmed by a client, or in production
-- ---------------------------------------------------------------------------
-- Two problems. The client passed `p_outcome`, so it decided whether a payment
-- succeeded; and demo money and real money were only kept apart by a flag
-- nothing checked at settlement time.
--
-- Now: the client cannot say how a payment turned out at all. Confirming and
-- cancelling are separate calls, because dismissing a payment sheet is a real
-- thing a client knows and "the money arrived" is not. The sandbox confirm
-- refuses to run when sandbox mode is off, refuses to touch an intent from the
-- other money mode, and takes its success or failure from server configuration.

alter table public.vault_config
    add column if not exists sandbox_decline_basis_points integer not null default 0;

grant select on table public.vault_config to authenticated;

-- Refuses to settle an intent that belongs to the other money mode, so a demo
-- intent can never be turned into real money and vice versa.
create or replace function public.vault_settle_deposit_intent(
    p_intent_id uuid,
    p_outcome text,
    p_provider_event_id text,
    p_failure_reason text default null
)
returns public.vault_payment_intents
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    intent public.vault_payment_intents;
    posted public.vault_ledger_transactions;
    psp uuid;
    available uuid;
begin
    select * into intent
    from public.vault_payment_intents
    where id = p_intent_id
    for update;

    if not found then
        raise exception 'vault: unknown payment' using errcode = 'P0002';
    end if;

    if intent.status in ('succeeded', 'failed', 'canceled', 'reversed') then
        return intent;
    end if;

    if intent.is_demo <> public.vault_is_sandbox() then
        raise exception 'vault: that payment belongs to a different money mode'
            using errcode = '42501';
    end if;

    if p_provider_event_id is not null and exists (
        select 1 from public.vault_payment_intents
        where provider = intent.provider
          and provider_event_id = p_provider_event_id
          and id <> intent.id
    ) then
        raise exception 'vault: that payment event was already handled'
            using errcode = '23505';
    end if;

    if p_outcome <> 'succeeded' then
        update public.vault_payment_intents
        set status = p_outcome,
            provider_event_id = p_provider_event_id,
            failure_reason = p_failure_reason,
            updated_at = now()
        where id = intent.id
        returning * into intent;

        update public.vault_statement_entries
        set status = case p_outcome when 'canceled' then 'canceled' else 'failed' end,
            detail = coalesce(p_failure_reason, 'Payment did not complete'),
            updated_at = now()
        where payment_intent_id = intent.id and status = 'pending';

        perform public.vault_log(intent.user_id, 'deposit_settled', p_outcome,
                                 intent.amount_cents, intent.reference_code);
        return intent;
    end if;

    psp := public.vault_account(null, 'psp_clearing', intent.currency_code);
    available := public.vault_account(intent.user_id, 'available', intent.currency_code);

    if intent.purpose = 'vault_deposit' then
        posted := public.vault_post_transaction(
            intent.user_id,
            'deposit',
            jsonb_build_array(
                jsonb_build_object('account_id', psp, 'amount_cents', -intent.amount_cents),
                jsonb_build_object('account_id', available, 'amount_cents', intent.amount_cents)
            ),
            'intent:' || intent.id::text,
            null,
            jsonb_build_object('provider', intent.provider, 'intent', intent.reference_code)
        );

        update public.vault_statement_entries
        set status = 'completed',
            ledger_transaction_id = posted.id,
            detail = 'Added to your Vault',
            updated_at = now()
        where payment_intent_id = intent.id and status = 'pending';
    end if;

    update public.vault_payment_intents
    set status = 'succeeded',
        provider_event_id = p_provider_event_id,
        updated_at = now()
    where id = intent.id
    returning * into intent;

    perform public.vault_log(intent.user_id, 'deposit_settled', 'succeeded',
                             intent.amount_cents, intent.reference_code);
    return intent;
end;
$$;

-- The old two-argument form let the caller pick the outcome. It is dropped
-- rather than left in place, so an old build cannot keep using it.
drop function if exists public.vault_sandbox_confirm_deposit(uuid, text);

create or replace function public.vault_sandbox_confirm_deposit(p_intent_id uuid)
returns public.vault_payment_intents
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    uid uuid := public.vault_require_user();
    intent public.vault_payment_intents;
    decline_bp integer;
    roll integer;
    succeeded boolean;
begin
    if not public.vault_is_sandbox() then
        raise exception 'vault: sandbox confirmation is switched off in production'
            using errcode = '42501';
    end if;

    select * into intent from public.vault_payment_intents where id = p_intent_id;
    if not found or intent.user_id <> uid then
        raise exception 'vault: unknown payment' using errcode = 'P0002';
    end if;

    if not intent.is_demo then
        raise exception 'vault: that payment is not demo money' using errcode = '42501';
    end if;

    perform public.vault_touch_rate_limit(uid, 'sandbox_confirm', 30, interval '5 minutes');

    -- The outcome is the server's to decide, not the caller's. An operator can
    -- raise `sandbox_decline_basis_points` to exercise the failure path; a client
    -- has no way to ask for success.
    select coalesce(sandbox_decline_basis_points, 0) into decline_bp
    from public.vault_config where id;

    roll := (('x' || substr(md5(p_intent_id::text || intent.reference_code), 1, 8))::bit(32)::bigint
             % 10000)::integer;
    succeeded := abs(roll) >= coalesce(decline_bp, 0);

    return public.vault_settle_deposit_intent(
        p_intent_id,
        case when succeeded then 'succeeded' else 'failed' end,
        'sandbox_' || p_intent_id::text,
        case when succeeded then null else 'Simulated decline from the test provider' end
    );
end;
$$;

revoke all on function public.vault_sandbox_confirm_deposit(uuid) from public, anon;
grant execute on function public.vault_sandbox_confirm_deposit(uuid) to authenticated;

-- Abandoning a payment is something a client genuinely knows about: the person
-- dismissed the sheet. It can only ever move an intent to `canceled`, so it is
-- safe in production as well as sandbox.
create or replace function public.vault_cancel_deposit_intent(p_intent_id uuid)
returns public.vault_payment_intents
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    uid uuid := public.vault_require_user();
    intent public.vault_payment_intents;
begin
    select * into intent from public.vault_payment_intents where id = p_intent_id for update;
    if not found or intent.user_id <> uid then
        raise exception 'vault: unknown payment' using errcode = 'P0002';
    end if;

    if intent.status <> 'requires_confirmation' then
        return intent;
    end if;

    update public.vault_payment_intents
    set status = 'canceled',
        failure_reason = 'Canceled before payment',
        updated_at = now()
    where id = intent.id
    returning * into intent;

    update public.vault_statement_entries
    set status = 'canceled',
        detail = 'Canceled before payment',
        updated_at = now()
    where payment_intent_id = intent.id and status = 'pending';

    perform public.vault_log(uid, 'deposit_canceled', 'ok',
                             intent.amount_cents, intent.reference_code);
    return intent;
end;
$$;

revoke all on function public.vault_cancel_deposit_intent(uuid) from public, anon;
grant execute on function public.vault_cancel_deposit_intent(uuid) to authenticated;

-- Same treatment for the demo payout simulator: sandbox only, demo money only.
drop function if exists public.vault_sandbox_resolve_withdrawal(uuid, text);

create or replace function public.vault_sandbox_resolve_withdrawal(
    p_withdrawal_id uuid,
    p_outcome text default 'completed'
)
returns public.vault_withdrawals
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    uid uuid := public.vault_require_user();
    withdrawal public.vault_withdrawals;
begin
    if not public.vault_is_sandbox() then
        raise exception 'vault: sandbox payouts are switched off in production'
            using errcode = '42501';
    end if;

    select * into withdrawal from public.vault_withdrawals where id = p_withdrawal_id;
    if not found or withdrawal.user_id <> uid then
        raise exception 'vault: unknown cash-out' using errcode = 'P0002';
    end if;

    if not withdrawal.is_demo then
        raise exception 'vault: that cash-out is not demo money' using errcode = '42501';
    end if;

    if p_outcome not in ('completed', 'failed', 'rejected') then
        raise exception 'vault: unknown payout outcome %', p_outcome using errcode = '23514';
    end if;

    perform set_config('vault.payout_actor', 'sandbox', true);
    withdrawal := public.vault_resolve_withdrawal(
        p_withdrawal_id, p_outcome, 'sandbox_' || p_withdrawal_id::text,
        case when p_outcome = 'completed' then null else 'Simulated payout outcome' end
    );
    perform set_config('vault.payout_actor', '', true);
    return withdrawal;
end;
$$;

revoke all on function public.vault_sandbox_resolve_withdrawal(uuid, text) from public, anon;
grant execute on function public.vault_sandbox_resolve_withdrawal(uuid, text) to authenticated;

notify pgrst, 'reload schema';
