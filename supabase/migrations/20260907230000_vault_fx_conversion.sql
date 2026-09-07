-- Convert, then transfer.
--
-- The wallet is one pot. A table or a cash-out can be another currency. Copying
-- the same cent count across units used to turn $20 into £20. These functions
-- convert at vault_fx_rates (the same table as VaultFX / HardcodedExchangeRateProvider)
-- and then post the transfer. Settlement JSON stays in table chips so poker
-- tests keep reading bought_in_cents / returned_cents as the seat, not the wallet.

-- ---------------------------------------------------------------------------
-- Published rates
-- ---------------------------------------------------------------------------

create table if not exists public.vault_fx_rates (
    currency_code text primary key,
    rate_per_usd numeric not null check (rate_per_usd > 0)
);

insert into public.vault_fx_rates (currency_code, rate_per_usd) values
    ('USD', 1),
    ('GBP', 0.79),
    ('EUR', 0.92),
    ('ILS', 3.72),
    ('CAD', 1.36),
    ('AUD', 1.51),
    ('JPY', 157.0),
    ('CHF', 0.89),
    ('CNY', 7.24),
    ('HKD', 7.81),
    ('SGD', 1.35),
    ('NZD', 1.64),
    ('SEK', 10.5),
    ('NOK', 10.7),
    ('DKK', 6.86),
    ('PLN', 3.99),
    ('CZK', 22.9),
    ('HUF', 360.0),
    ('RON', 4.58),
    ('BGN', 1.80),
    ('TRY', 32.6),
    ('MXN', 18.0),
    ('BRL', 5.42),
    ('ARS', 905.0),
    ('CLP', 940.0),
    ('COP', 4100.0),
    ('PEN', 3.75),
    ('ZAR', 18.2),
    ('INR', 83.5),
    ('KRW', 1380.0),
    ('THB', 36.7),
    ('MYR', 4.71),
    ('IDR', 16200.0),
    ('PHP', 58.5),
    ('VND', 25400.0),
    ('AED', 3.67),
    ('SAR', 3.75),
    ('QAR', 3.64),
    ('KWD', 0.31),
    ('BHD', 0.38),
    ('OMR', 0.38),
    ('EGP', 48.0),
    ('MAD', 9.95),
    ('NGN', 1500.0),
    ('KES', 129.0),
    ('GHS', 15.0),
    ('RUB', 89.0),
    ('UAH', 40.5)
on conflict (currency_code) do update
    set rate_per_usd = excluded.rate_per_usd;

alter table public.vault_fx_rates enable row level security;

revoke all on table public.vault_fx_rates from public, anon, authenticated;
grant select on table public.vault_fx_rates to authenticated, service_role;

drop policy if exists vault_fx_rates_read on public.vault_fx_rates;
create policy vault_fx_rates_read on public.vault_fx_rates
    for select to authenticated
    using (true);

-- ---------------------------------------------------------------------------
-- House FX accounts: one per currency so mixed-unit postings still sum to 0
-- ---------------------------------------------------------------------------

do $$
declare
    r record;
begin
    for r in
        select conname
        from pg_constraint
        where conrelid = 'public.vault_accounts'::regclass
          and contype = 'c'
          and pg_get_constraintdef(oid) ~* 'kind'
          and pg_get_constraintdef(oid) !~* 'player_kind'
          and pg_get_constraintdef(oid) !~* 'table_code'
          and pg_get_constraintdef(oid) !~* 'never_negative'
    loop
        execute format('alter table public.vault_accounts drop constraint %I', r.conname);
    end loop;
end $$;

alter table public.vault_accounts
    add constraint vault_accounts_kind_check
    check (kind in (
        'available', 'in_play', 'pending_withdrawal',
        'psp_clearing', 'payout_clearing', 'fees', 'fx'
    ));

-- ---------------------------------------------------------------------------
-- Conversion helpers
-- ---------------------------------------------------------------------------

create or replace function public.vault_fx_rate(p_currency text)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    code text := upper(trim(coalesce(p_currency, '')));
    rate numeric;
begin
    if code = '' then
        raise exception 'vault: unknown currency' using errcode = '23514';
    end if;
    if code = 'USD' then
        return 1;
    end if;

    select rate_per_usd into rate
    from public.vault_fx_rates
    where currency_code = code;

    if not found then
        raise exception 'vault: no exchange rate for %', code using errcode = 'P0002';
    end if;
    return rate;
end;
$$;

create or replace function public.vault_convert_cents(
    p_amount_cents bigint,
    p_from text,
    p_to text
)
returns bigint
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    source_code text := upper(trim(coalesce(p_from, '')));
    target_code text := upper(trim(coalesce(p_to, '')));
    converted bigint;
begin
    if p_amount_cents = 0 then
        return 0;
    end if;
    if source_code = target_code then
        return p_amount_cents;
    end if;

    converted := round(
        p_amount_cents::numeric
        * public.vault_fx_rate(target_code)
        / public.vault_fx_rate(source_code)
    );

    if p_amount_cents > 0 and converted <= 0 then
        raise exception 'vault: that amount is too small to convert'
            using errcode = '23514';
    end if;
    if p_amount_cents < 0 and converted >= 0 then
        raise exception 'vault: that amount is too small to convert'
            using errcode = '23514';
    end if;

    return converted;
end;
$$;

create or replace function public.vault_wallet_currency(p_user_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    wallet_currency text;
begin
    select currency_code into wallet_currency
    from public.vault_accounts
    where owner_user_id = p_user_id and kind = 'available'
    order by created_at
    limit 1;

    return coalesce(wallet_currency, 'USD');
end;
$$;

-- Four legs when the currencies differ so each currency's books still balance:
-- from −A, fx(from) +A, fx(to) −B, to +B. Same currency stays two legs.
create or replace function public.vault_fx_moves(
    p_from uuid,
    p_from_cents bigint,
    p_from_currency text,
    p_to uuid,
    p_to_cents bigint,
    p_to_currency text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    from_code text := upper(trim(p_from_currency));
    to_code text := upper(trim(p_to_currency));
    from_fx uuid;
    to_fx uuid;
begin
    if from_code = to_code then
        if p_from_cents <> p_to_cents then
            raise exception 'vault: same-currency transfer must keep the same cents'
                using errcode = '23514';
        end if;
        return jsonb_build_array(
            jsonb_build_object('account_id', p_from, 'amount_cents', -p_from_cents),
            jsonb_build_object('account_id', p_to, 'amount_cents', p_to_cents)
        );
    end if;

    from_fx := public.vault_account(null, 'fx', from_code);
    to_fx := public.vault_account(null, 'fx', to_code);

    return jsonb_build_array(
        jsonb_build_object('account_id', p_from, 'amount_cents', -p_from_cents),
        jsonb_build_object('account_id', from_fx, 'amount_cents', p_from_cents),
        jsonb_build_object('account_id', to_fx, 'amount_cents', -p_to_cents),
        jsonb_build_object('account_id', p_to, 'amount_cents', p_to_cents)
    );
end;
$$;

revoke all on function public.vault_fx_rate(text) from public, anon;
revoke all on function public.vault_convert_cents(bigint, text, text) from public, anon;
revoke all on function public.vault_wallet_currency(uuid) from public, anon;
revoke all on function public.vault_fx_moves(uuid, bigint, text, uuid, bigint, text)
    from public, anon;
grant execute on function public.vault_fx_rate(text) to authenticated, service_role;
grant execute on function public.vault_convert_cents(bigint, text, text)
    to authenticated, service_role;
grant execute on function public.vault_wallet_currency(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Withdrawals remember the wallet debit that funded a payout in another unit
-- ---------------------------------------------------------------------------

alter table public.vault_withdrawals
    add column if not exists source_amount_cents bigint,
    add column if not exists source_currency_code text;

update public.vault_withdrawals
set source_amount_cents = coalesce(source_amount_cents, amount_cents),
    source_currency_code = coalesce(nullif(source_currency_code, ''), currency_code)
where source_amount_cents is null
   or source_currency_code is null;

alter table public.vault_withdrawals
    alter column source_amount_cents set default 0,
    alter column source_currency_code set default 'USD';

alter table public.vault_withdrawals
    alter column source_amount_cents set not null,
    alter column source_currency_code set not null;

-- ---------------------------------------------------------------------------
-- Summary: convert in-play chips into the wallet before summing
-- ---------------------------------------------------------------------------

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
    wallet_currency := public.vault_wallet_currency(uid);

    select coalesce(sum(balance_cents) filter (where kind = 'available'), 0),
           coalesce(sum(balance_cents) filter (where kind = 'pending_withdrawal'), 0)
    into available, pending_withdrawal
    from public.vault_accounts
    where owner_user_id = uid;

    select coalesce(sum(public.vault_convert_cents(
               balance_cents, currency_code, wallet_currency
           )), 0)
    into in_play
    from public.vault_accounts
    where owner_user_id = uid and kind = 'in_play';

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

-- ---------------------------------------------------------------------------
-- Buy-in: debit the wallet at the rate, credit the seat in table chips
-- ---------------------------------------------------------------------------

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
    player_key text;
    tbl public.vault_tables;
    intent public.vault_payment_intents;
    posted public.vault_ledger_transactions;
    source_account uuid;
    in_play uuid;
    stake public.vault_table_stakes;
    wallet_currency text;
    source_cents bigint;
    source_currency text;
    moves jsonb;
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

    wallet_currency := public.vault_wallet_currency(uid);
    perform public.vault_open(wallet_currency);
    perform public.vault_account(null, 'fx', tbl.currency_code);
    in_play := public.vault_account(uid, 'in_play', tbl.currency_code, code);

    if p_source = 'vault' then
        source_cents := public.vault_convert_cents(p_amount_cents, tbl.currency_code, wallet_currency);
        source_currency := wallet_currency;
        source_account := public.vault_account(uid, 'available', wallet_currency);

        if (select balance_cents from public.vault_accounts
            where id = source_account for update) < source_cents then
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
        if intent.amount_cents <> public.vault_convert_cents(
            p_amount_cents, tbl.currency_code, intent.currency_code
        ) then
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

        source_cents := intent.amount_cents;
        source_currency := intent.currency_code;
        source_account := public.vault_account(null, 'psp_clearing', intent.currency_code);
    else
        raise exception 'vault: unknown payment source %', p_source using errcode = '23514';
    end if;

    moves := public.vault_fx_moves(
        source_account, source_cents, source_currency,
        in_play, p_amount_cents, tbl.currency_code
    );

    posted := public.vault_post_transaction(
        uid,
        case p_source when 'vault' then 'table_buy_in_vault' else 'table_buy_in_direct' end,
        moves,
        p_idempotency_key,
        code,
        jsonb_build_object(
            'source', p_source,
            'player_key', player_key,
            'table_cents', p_amount_cents,
            'wallet_cents', source_cents,
            'table_currency', tbl.currency_code,
            'wallet_currency', source_currency
        )
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
            case
                when p_source = 'vault' and tbl.currency_code = source_currency then
                    'Moved from Available into In Play'
                when p_source = 'vault' then
                    'Converted from ' || source_currency || ' into ' || tbl.currency_code || ' on the table'
                else
                    'Paid straight onto the table'
            end
        );
    end if;

    perform public.vault_log(uid, 'table_buy_in', 'ok', p_amount_cents,
                             posted.reference_code, code,
                             jsonb_build_object(
                                 'source', p_source,
                                 'wallet_cents', source_cents
                             ));

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
-- Leave: return table chips, credit the wallet at the rate
-- ---------------------------------------------------------------------------

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
    wallet_currency text;
    final_cents bigint;
    withheld bigint := 0;
    return_cents bigint;
    wallet_cents bigint := 0;
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

    wallet_currency := public.vault_wallet_currency(uid);

    if stake.status = 'left' then
        return jsonb_build_object(
            'invite_code', code,
            'bought_in_cents', stake.total_bought_in_cents,
            'returned_cents', stake.returned_cents,
            'net_cents', stake.returned_cents - stake.total_bought_in_cents,
            'wallet_returned_cents', public.vault_convert_cents(
                stake.returned_cents, tbl.currency_code, wallet_currency
            ),
            'table_currency', tbl.currency_code,
            'wallet_currency', wallet_currency,
            'reference_code', '',
            'already_settled', true
        );
    end if;

    perform public.poker_sweep_timeouts(code);
    withheld := public.poker_withdraw_player(code, stake.player_key);
    withheld := public.poker_live_committed_cents(code, stake.player_key);

    in_play := public.vault_account(uid, 'in_play', tbl.currency_code, code);
    available := public.vault_account(uid, 'available', wallet_currency);

    select balance_cents into final_cents
    from public.vault_accounts where id = in_play for update;

    if withheld > final_cents then
        withheld := final_cents;
    end if;
    return_cents := final_cents - withheld;
    bought_in := stake.total_bought_in_cents;

    if return_cents > 0 then
        wallet_cents := public.vault_convert_cents(return_cents, tbl.currency_code, wallet_currency);
        posted := public.vault_post_transaction(
            uid, 'table_return',
            public.vault_fx_moves(
                in_play, return_cents, tbl.currency_code,
                available, wallet_cents, wallet_currency
            ),
            p_idempotency_key, code,
            jsonb_build_object(
                'bought_in_cents', bought_in,
                'withheld_cents', withheld,
                'table_cents', return_cents,
                'wallet_cents', wallet_cents
            )
        );

        perform public.vault_add_statement(
            uid, 'table_return', 'completed', 0, wallet_currency,
            posted.id, null, null, code,
            case
                when tbl.currency_code = wallet_currency then
                    'Returned from the table to your Vault'
                else
                    'Converted from ' || tbl.currency_code || ' back into ' || wallet_currency
            end
        );
    end if;

    update public.vault_table_stakes
    set status = 'left',
        left_at = now(),
        in_play_cents = withheld,
        returned_cents = returned_cents + return_cents
    where invite_code = code and user_id = uid;

    perform public.vault_log(uid, 'table_leave', 'ok', return_cents,
                             coalesce(posted.reference_code, 'none'), code,
                             jsonb_build_object(
                                 'withheld_cents', withheld,
                                 'wallet_cents', wallet_cents
                             ));

    return jsonb_build_object(
        'invite_code', code,
        'bought_in_cents', bought_in,
        'returned_cents', return_cents,
        'net_cents', return_cents - bought_in,
        'wallet_returned_cents', wallet_cents,
        'table_currency', tbl.currency_code,
        'wallet_currency', wallet_currency,
        'reference_code', coalesce(posted.reference_code, ''),
        'already_settled', false
    );
end;
$$;

revoke all on function public.vault_leave_table(text, text) from public, anon;
grant execute on function public.vault_leave_table(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Cash-out: amount is the payout; reserve the converted wallet debit
-- ---------------------------------------------------------------------------

create or replace function public.vault_request_withdrawal(
    p_amount_cents bigint,
    p_idempotency_key text,
    p_currency text default 'USD'
)
returns public.vault_withdrawals
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    uid uuid := public.vault_require_user();
    config public.vault_config;
    withdrawal public.vault_withdrawals;
    available uuid;
    available_cents bigint;
    reserved uuid;
    posted public.vault_ledger_transactions;
    fee bigint;
    payout_currency text := upper(trim(coalesce(p_currency, 'USD')));
    wallet_currency text;
    wallet_cents bigint;
begin
    select * into withdrawal
    from public.vault_withdrawals
    where user_id = uid and idempotency_key = p_idempotency_key;

    if found then
        return withdrawal;
    end if;

    perform public.vault_fx_rate(payout_currency);
    wallet_currency := public.vault_wallet_currency(uid);
    wallet_cents := public.vault_convert_cents(p_amount_cents, payout_currency, wallet_currency);

    perform public.vault_touch_rate_limit(uid, 'withdrawal', 10, interval '10 minutes');
    perform public.vault_assert_allowed(uid, 'withdrawal', wallet_cents);

    select * into config from public.vault_config where id;

    if wallet_cents < config.withdrawal_min_cents then
        raise exception 'vault: the smallest cash-out is % cents', config.withdrawal_min_cents
            using errcode = '23514';
    end if;

    perform public.vault_open(wallet_currency);
    available := public.vault_account(uid, 'available', wallet_currency);
    reserved := public.vault_account(uid, 'pending_withdrawal', wallet_currency);

    select balance_cents into available_cents
    from public.vault_accounts where id = available for update;

    if wallet_cents > available_cents then
        raise exception 'vault: you can cash out at most % cents right now', available_cents
            using errcode = '23514';
    end if;

    fee := config.withdrawal_fee_flat_cents
         + (p_amount_cents * config.withdrawal_fee_basis_points) / 10000;

    if fee >= p_amount_cents then
        raise exception 'vault: that is less than the cash-out fee' using errcode = '23514';
    end if;

    posted := public.vault_post_transaction(
        uid, 'withdrawal_request',
        jsonb_build_array(
            jsonb_build_object('account_id', available, 'amount_cents', -wallet_cents),
            jsonb_build_object('account_id', reserved, 'amount_cents', wallet_cents)
        ),
        p_idempotency_key, null,
        jsonb_build_object(
            'fee_cents', fee,
            'payout_cents', p_amount_cents,
            'payout_currency', payout_currency,
            'wallet_cents', wallet_cents
        )
    );

    insert into public.vault_withdrawals (
        user_id, reference_code, amount_cents, fee_cents, net_cents,
        currency_code, source_amount_cents, source_currency_code,
        idempotency_key, is_demo
    )
    values (
        uid, public.vault_reference_code('CO'), p_amount_cents, fee,
        p_amount_cents - fee, payout_currency, wallet_cents, wallet_currency,
        p_idempotency_key, public.vault_is_sandbox()
    )
    returning * into withdrawal;

    perform public.vault_add_statement(
        uid, 'withdrawal_request', 'pending', 0, payout_currency,
        posted.id, null, withdrawal.id, null,
        case
            when payout_currency = wallet_currency then 'Cash-out requested'
            else 'Cash-out requested in ' || payout_currency
        end
    );

    perform public.vault_log(uid, 'withdrawal_requested', 'ok', p_amount_cents,
                             withdrawal.reference_code, null,
                             jsonb_build_object(
                                 'wallet_cents', wallet_cents,
                                 'payout_currency', payout_currency
                             ));
    return withdrawal;
end;
$$;

create or replace function public.vault_complete_withdrawal_moves(
    p_reserved uuid,
    p_source_cents bigint,
    p_source_currency text,
    p_payout uuid,
    p_fees uuid,
    p_amount_cents bigint,
    p_net_cents bigint,
    p_fee_cents bigint,
    p_payout_currency text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    source_code text := upper(trim(p_source_currency));
    payout_code text := upper(trim(p_payout_currency));
    source_fx uuid;
    payout_fx uuid;
begin
    if source_code = payout_code then
        return jsonb_build_array(
            jsonb_build_object('account_id', p_reserved, 'amount_cents', -p_source_cents),
            jsonb_build_object('account_id', p_payout, 'amount_cents', p_net_cents),
            jsonb_build_object('account_id', p_fees, 'amount_cents', p_fee_cents)
        );
    end if;

    source_fx := public.vault_account(null, 'fx', source_code);
    payout_fx := public.vault_account(null, 'fx', payout_code);

    -- Reserved wallet cents convert into the payout currency; the payout rail
    -- receives the net and the operator keeps the fee. Signed cents sum to 0.
    return jsonb_build_array(
        jsonb_build_object('account_id', p_reserved, 'amount_cents', -p_source_cents),
        jsonb_build_object('account_id', source_fx, 'amount_cents', p_source_cents),
        jsonb_build_object('account_id', payout_fx, 'amount_cents', -p_amount_cents),
        jsonb_build_object('account_id', p_payout, 'amount_cents', p_net_cents),
        jsonb_build_object('account_id', p_fees, 'amount_cents', p_fee_cents)
    );
end;
$$;

revoke all on function public.vault_complete_withdrawal_moves(
    uuid, bigint, text, uuid, uuid, bigint, bigint, bigint, text
) from public, anon;

create or replace function public.vault_resolve_withdrawal(
    p_withdrawal_id uuid,
    p_outcome text,
    p_provider_transfer_id text default null,
    p_failure_reason text default null
)
returns public.vault_withdrawals
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    withdrawal public.vault_withdrawals;
    reserved uuid;
    available uuid;
    payout uuid;
    fees uuid;
    posted public.vault_ledger_transactions;
    source_cents bigint;
    source_currency text;
    payout_currency text;
begin
    if auth.uid() is not null
       and coalesce(current_setting('vault.payout_actor', true), '') <> 'sandbox' then
        raise exception 'vault: cash-outs are settled by the payout provider'
            using errcode = '42501';
    end if;

    select * into withdrawal
    from public.vault_withdrawals
    where id = p_withdrawal_id
    for update;

    if not found then
        raise exception 'vault: unknown cash-out' using errcode = 'P0002';
    end if;

    if withdrawal.status in ('completed', 'rejected', 'canceled', 'failed') then
        return withdrawal;
    end if;

    source_cents := coalesce(nullif(withdrawal.source_amount_cents, 0), withdrawal.amount_cents);
    source_currency := coalesce(nullif(withdrawal.source_currency_code, ''), withdrawal.currency_code);
    payout_currency := withdrawal.currency_code;

    reserved := public.vault_account(withdrawal.user_id, 'pending_withdrawal', source_currency);
    available := public.vault_account(withdrawal.user_id, 'available', source_currency);
    payout := public.vault_account(null, 'payout_clearing', payout_currency);
    fees := public.vault_account(null, 'fees', payout_currency);

    if p_outcome = 'completed' then
        posted := public.vault_post_transaction(
            withdrawal.user_id, 'withdrawal_completed',
            public.vault_complete_withdrawal_moves(
                reserved, source_cents, source_currency,
                payout, fees,
                withdrawal.amount_cents, withdrawal.net_cents, withdrawal.fee_cents,
                payout_currency
            ),
            'withdrawal_complete:' || withdrawal.id::text, null,
            jsonb_build_object('transfer', p_provider_transfer_id)
        );

        perform public.vault_add_statement(
            withdrawal.user_id, 'withdrawal_completed', 'completed',
            -withdrawal.amount_cents, payout_currency,
            posted.id, null, withdrawal.id, null, 'Paid out'
        );
    else
        posted := public.vault_post_transaction(
            withdrawal.user_id, 'withdrawal_' || p_outcome,
            jsonb_build_array(
                jsonb_build_object('account_id', reserved, 'amount_cents', -source_cents),
                jsonb_build_object('account_id', available, 'amount_cents', source_cents)
            ),
            'withdrawal_' || p_outcome || ':' || withdrawal.id::text, null,
            jsonb_build_object('reason', p_failure_reason)
        );

        perform public.vault_add_statement(
            withdrawal.user_id, 'withdrawal_' || p_outcome,
            case p_outcome when 'rejected' then 'rejected'
                           when 'canceled' then 'canceled'
                           else 'failed' end,
            0, source_currency, posted.id, null, withdrawal.id, null,
            coalesce(p_failure_reason, 'Returned to your available balance')
        );
    end if;

    update public.vault_withdrawals
    set status = p_outcome,
        provider_transfer_id = p_provider_transfer_id,
        failure_reason = p_failure_reason,
        resolved_at = now()
    where id = withdrawal.id
    returning * into withdrawal;

    update public.vault_statement_entries
    set status = case p_outcome when 'completed' then 'completed' else 'canceled' end,
        updated_at = now()
    where withdrawal_id = withdrawal.id and kind = 'withdrawal_request' and status = 'pending';

    perform public.vault_log(withdrawal.user_id, 'withdrawal_resolved', p_outcome,
                             withdrawal.amount_cents, withdrawal.reference_code);
    return withdrawal;
end;
$$;

create or replace function public.vault_cancel_withdrawal(p_withdrawal_id uuid)
returns public.vault_withdrawals
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    uid uuid := public.vault_require_user();
    withdrawal public.vault_withdrawals;
    reserved uuid;
    available uuid;
    posted public.vault_ledger_transactions;
    source_cents bigint;
    source_currency text;
begin
    select * into withdrawal
    from public.vault_withdrawals
    where id = p_withdrawal_id
    for update;

    if not found or withdrawal.user_id <> uid then
        raise exception 'vault: unknown cash-out' using errcode = 'P0002';
    end if;

    if withdrawal.status <> 'pending' then
        return withdrawal;
    end if;

    source_cents := coalesce(nullif(withdrawal.source_amount_cents, 0), withdrawal.amount_cents);
    source_currency := coalesce(nullif(withdrawal.source_currency_code, ''), withdrawal.currency_code);

    reserved := public.vault_account(uid, 'pending_withdrawal', source_currency);
    available := public.vault_account(uid, 'available', source_currency);

    posted := public.vault_post_transaction(
        uid, 'withdrawal_canceled',
        jsonb_build_array(
            jsonb_build_object('account_id', reserved, 'amount_cents', -source_cents),
            jsonb_build_object('account_id', available, 'amount_cents', source_cents)
        ),
        'withdrawal_canceled:' || withdrawal.id::text
    );

    update public.vault_withdrawals
    set status = 'canceled', resolved_at = now()
    where id = withdrawal.id
    returning * into withdrawal;

    update public.vault_statement_entries
    set status = 'canceled', updated_at = now()
    where withdrawal_id = withdrawal.id and status = 'pending';

    perform public.vault_add_statement(
        uid, 'withdrawal_canceled', 'canceled', 0, source_currency,
        posted.id, null, withdrawal.id, null, 'You canceled this cash-out'
    );

    perform public.vault_log(uid, 'withdrawal_canceled', 'ok',
                             withdrawal.amount_cents, withdrawal.reference_code);
    return withdrawal;
end;
$$;
