-- Pot Master — Vault: private player wallet backed by an immutable double-entry ledger.
--
-- Paste this whole file into the Supabase SQL Editor and click Run. It is safe
-- to run more than once.
--
-- SANDBOX PHASE
-- =============
-- Every amount created by this schema is demo money. `vault_config.sandbox_mode`
-- is true, which is what allows the app to confirm its own mock Apple Pay
-- deposits. Turning sandbox mode off closes that door: deposits can then only be
-- settled by a verified payment-provider webhook running as `service_role`, and
-- withdrawals can only be paid out by an operator process. No real payment
-- provider is wired up yet.
--
-- MODEL
-- =====
-- Money lives in accounts and only ever moves between them. Every movement is a
-- transaction holding two or more entries whose signed cents sum to exactly
-- zero, so the books balance by construction. Nothing rewrites a balance: the
-- balance column on an account is a running total maintained inside the same
-- database transaction as the entries that moved it, and
-- `vault_reconcile_account` re-derives it from the entries to prove they agree.
--
-- Amounts are integer cents (bigint) everywhere. There is no floating point.
--
-- PRIVACY
-- =======
-- Row level security lets a signed-in player read only their own accounts,
-- transactions, statement rows, deposits and withdrawals. No role other than
-- `service_role` may write to any of these tables directly — every mutation goes
-- through a `security definer` function that re-checks who the caller is. The
-- only financial fact another player can read is the chips a seat has in play at
-- a table they are also seated at, exposed by `vault_table_chips`.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

create table if not exists public.vault_config (
    id boolean primary key default true,
    sandbox_mode boolean not null default true,
    deposit_min_cents bigint not null default 500,
    deposit_max_cents bigint not null default 50000,
    daily_deposit_limit_cents bigint not null default 100000,
    withdrawal_min_cents bigint not null default 1000,
    withdrawal_fee_flat_cents bigint not null default 0,
    withdrawal_fee_basis_points integer not null default 0,
    updated_at timestamptz not null default now(),
    constraint vault_config_singleton check (id)
);

insert into public.vault_config (id) values (true) on conflict (id) do nothing;

create or replace function public.vault_is_sandbox()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select coalesce((select sandbox_mode from public.vault_config where id), true);
$$;

-- ---------------------------------------------------------------------------
-- Compliance
-- ---------------------------------------------------------------------------
-- Every gate a real-money build has to clear lives here so the checks have a
-- single home. In sandbox they are permissive by default; an operator flips a
-- row to block a player, and the same code path enforces it in production.

create table if not exists public.vault_compliance_profiles (
    user_id uuid primary key references auth.users (id) on delete cascade,
    jurisdiction_code text not null default 'XX',
    jurisdiction_status text not null default 'sandbox'
        check (jurisdiction_status in ('sandbox', 'allowed', 'blocked', 'unknown')),
    account_status text not null default 'active'
        check (account_status in ('active', 'restricted', 'suspended', 'closed')),
    restriction_reason text,
    identity_status text not null default 'unverified'
        check (identity_status in ('unverified', 'pending', 'verified', 'rejected')),
    sanctions_status text not null default 'not_screened'
        check (sanctions_status in ('not_screened', 'clear', 'review', 'hit')),
    self_excluded_until timestamptz,
    daily_deposit_limit_cents bigint,
    daily_loss_limit_cents bigint,
    session_limit_minutes integer,
    payout_method_status text not null default 'none'
        check (payout_method_status in ('none', 'pending', 'verified', 'rejected')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Accounts
-- ---------------------------------------------------------------------------
-- `available`          spendable and withdrawable money held for a player
-- `in_play`            money committed to one table by one player
-- `pending_withdrawal` money reserved while a cash-out is being processed
-- `psp_clearing`       the outside world money arrives from
-- `payout_clearing`    the outside world money leaves to
-- `fees`               fees retained by the operator
--
-- Player accounts may never go negative. The three system accounts are expected
-- to: they are the mirror of everything held on behalf of players.

create table if not exists public.vault_accounts (
    id uuid primary key default gen_random_uuid(),
    owner_user_id uuid references auth.users (id) on delete cascade,
    kind text not null check (kind in (
        'available', 'in_play', 'pending_withdrawal',
        'psp_clearing', 'payout_clearing', 'fees'
    )),
    table_invite_code text,
    currency_code text not null default 'USD',
    balance_cents bigint not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint vault_accounts_player_kind_has_owner check (
        (kind in ('available', 'in_play', 'pending_withdrawal')) = (owner_user_id is not null)
    ),
    constraint vault_accounts_table_code_only_in_play check (
        (kind = 'in_play') = (table_invite_code is not null)
    ),
    constraint vault_accounts_player_never_negative check (
        owner_user_id is null or balance_cents >= 0
    )
);

create unique index if not exists vault_accounts_player_unique
    on public.vault_accounts (owner_user_id, kind, coalesce(table_invite_code, ''))
    where owner_user_id is not null;

create unique index if not exists vault_accounts_system_unique
    on public.vault_accounts (kind, currency_code)
    where owner_user_id is null;

create index if not exists vault_accounts_table_idx
    on public.vault_accounts (table_invite_code)
    where table_invite_code is not null;

-- ---------------------------------------------------------------------------
-- Immutable double-entry ledger
-- ---------------------------------------------------------------------------

create table if not exists public.vault_ledger_transactions (
    id uuid primary key default gen_random_uuid(),
    reference_code text not null unique,
    user_id uuid references auth.users (id) on delete set null,
    kind text not null,
    idempotency_key text,
    table_invite_code text,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create unique index if not exists vault_ledger_transactions_idempotency
    on public.vault_ledger_transactions (user_id, idempotency_key)
    where idempotency_key is not null;

create index if not exists vault_ledger_transactions_user_idx
    on public.vault_ledger_transactions (user_id, created_at desc);

create table if not exists public.vault_ledger_entries (
    id uuid primary key default gen_random_uuid(),
    transaction_id uuid not null references public.vault_ledger_transactions (id) on delete restrict,
    account_id uuid not null references public.vault_accounts (id) on delete restrict,
    amount_cents bigint not null check (amount_cents <> 0),
    created_at timestamptz not null default now()
);

create index if not exists vault_ledger_entries_account_idx
    on public.vault_ledger_entries (account_id, created_at desc);
create index if not exists vault_ledger_entries_transaction_idx
    on public.vault_ledger_entries (transaction_id);

create or replace function public.vault_block_ledger_rewrite()
returns trigger
language plpgsql
as $$
begin
    raise exception 'vault ledger rows are immutable';
end;
$$;

drop trigger if exists vault_ledger_transactions_immutable on public.vault_ledger_transactions;
create trigger vault_ledger_transactions_immutable
    before update or delete on public.vault_ledger_transactions
    for each row execute function public.vault_block_ledger_rewrite();

drop trigger if exists vault_ledger_entries_immutable on public.vault_ledger_entries;
create trigger vault_ledger_entries_immutable
    before update or delete on public.vault_ledger_entries
    for each row execute function public.vault_block_ledger_rewrite();

-- ---------------------------------------------------------------------------
-- Statement — what the player reads in Transaction History
-- ---------------------------------------------------------------------------
-- The ledger is the truth and never changes. A statement row is the readable
-- face of one event and does carry a status, because a deposit can be pending
-- before it is completed and a cash-out can be rejected after it is requested.

create table if not exists public.vault_statement_entries (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    reference_code text not null unique,
    kind text not null check (kind in (
        'deposit', 'deposit_reversed',
        'table_buy_in_vault', 'table_buy_in_direct',
        'table_winnings', 'table_loss', 'table_return', 'table_refund',
        'withdrawal_request', 'withdrawal_completed', 'withdrawal_rejected',
        'withdrawal_canceled', 'withdrawal_failed',
        'adjustment', 'chargeback'
    )),
    status text not null default 'completed' check (status in (
        'pending', 'completed', 'failed', 'canceled', 'rejected', 'reversed'
    )),
    -- Signed against the player's total vault: a deposit is positive, a
    -- completed withdrawal is negative, a buy-in that only moves money from
    -- available into in-play is zero.
    amount_cents bigint not null,
    currency_code text not null default 'USD',
    ledger_transaction_id uuid references public.vault_ledger_transactions (id) on delete set null,
    payment_intent_id uuid,
    withdrawal_id uuid,
    table_invite_code text,
    is_demo boolean not null default true,
    detail text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists vault_statement_entries_user_idx
    on public.vault_statement_entries (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Deposits
-- ---------------------------------------------------------------------------
-- A deposit intent is an instruction, not money. It becomes money only when the
-- backend settles it — from a signed provider webhook in production, or from the
-- sandbox confirm function while `sandbox_mode` is on.

create table if not exists public.vault_payment_intents (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    reference_code text not null unique,
    provider text not null default 'mock_apple_pay',
    provider_intent_id text,
    provider_event_id text,
    purpose text not null default 'vault_deposit'
        check (purpose in ('vault_deposit', 'table_buy_in')),
    amount_cents bigint not null check (amount_cents > 0),
    currency_code text not null default 'USD',
    status text not null default 'requires_confirmation' check (status in (
        'requires_confirmation', 'processing', 'succeeded',
        'failed', 'canceled', 'reversed'
    )),
    table_invite_code text,
    idempotency_key text not null,
    consumed_at timestamptz,
    failure_reason text,
    is_demo boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (user_id, idempotency_key)
);

create unique index if not exists vault_payment_intents_provider_event
    on public.vault_payment_intents (provider, provider_event_id)
    where provider_event_id is not null;

create index if not exists vault_payment_intents_user_idx
    on public.vault_payment_intents (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Withdrawals
-- ---------------------------------------------------------------------------

create table if not exists public.vault_withdrawals (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    reference_code text not null unique,
    provider text not null default 'mock_payout',
    provider_transfer_id text,
    amount_cents bigint not null check (amount_cents > 0),
    fee_cents bigint not null default 0 check (fee_cents >= 0),
    net_cents bigint not null check (net_cents >= 0),
    currency_code text not null default 'USD',
    status text not null default 'pending' check (status in (
        'pending', 'processing', 'completed', 'rejected', 'canceled', 'failed'
    )),
    idempotency_key text not null,
    failure_reason text,
    is_demo boolean not null default true,
    requested_at timestamptz not null default now(),
    resolved_at timestamptz,
    unique (user_id, idempotency_key)
);

create index if not exists vault_withdrawals_user_idx
    on public.vault_withdrawals (user_id, requested_at desc);

-- ---------------------------------------------------------------------------
-- Tables and stakes
-- ---------------------------------------------------------------------------
-- The backend keeps its own record of who is sitting at a table with how much,
-- separate from the shared `open_tables` row the app syncs for gameplay. Chips
-- in play are the only figure other players can read.

create table if not exists public.vault_tables (
    invite_code text primary key,
    host_user_id uuid not null references auth.users (id) on delete cascade,
    currency_code text not null default 'USD',
    min_buy_in_cents bigint not null default 1000 check (min_buy_in_cents > 0),
    max_buy_in_cents bigint not null default 20000 check (max_buy_in_cents > 0),
    status text not null default 'open' check (status in ('open', 'settling', 'closed')),
    is_demo boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint vault_tables_buy_in_range check (max_buy_in_cents >= min_buy_in_cents)
);

create table if not exists public.vault_table_stakes (
    id uuid primary key default gen_random_uuid(),
    invite_code text not null references public.vault_tables (invite_code) on delete cascade,
    user_id uuid not null references auth.users (id) on delete cascade,
    player_key text not null,
    display_name text not null default 'Player',
    total_bought_in_cents bigint not null default 0 check (total_bought_in_cents >= 0),
    in_play_cents bigint not null default 0 check (in_play_cents >= 0),
    returned_cents bigint not null default 0 check (returned_cents >= 0),
    status text not null default 'seated' check (status in ('seated', 'left')),
    seated_at timestamptz not null default now(),
    left_at timestamptz,
    unique (invite_code, user_id)
);

create index if not exists vault_table_stakes_invite_idx
    on public.vault_table_stakes (invite_code);

-- ---------------------------------------------------------------------------
-- Audit, rate limits, responsible gaming
-- ---------------------------------------------------------------------------

create table if not exists public.vault_audit_log (
    id bigserial primary key,
    user_id uuid references auth.users (id) on delete set null,
    actor_user_id uuid,
    action text not null,
    outcome text not null default 'ok',
    amount_cents bigint,
    reference_code text,
    table_invite_code text,
    detail jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create index if not exists vault_audit_log_user_idx
    on public.vault_audit_log (user_id, created_at desc);

drop trigger if exists vault_audit_log_immutable on public.vault_audit_log;
create trigger vault_audit_log_immutable
    before update or delete on public.vault_audit_log
    for each row execute function public.vault_block_ledger_rewrite();

create table if not exists public.vault_rate_limits (
    user_id uuid not null references auth.users (id) on delete cascade,
    bucket text not null,
    window_started_at timestamptz not null default now(),
    hits integer not null default 0,
    primary key (user_id, bucket)
);

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------
-- Read your own rows, write nothing. Every write goes through a definer
-- function below, which is the only place authorisation is decided.

alter table public.vault_config enable row level security;
alter table public.vault_compliance_profiles enable row level security;
alter table public.vault_accounts enable row level security;
alter table public.vault_ledger_transactions enable row level security;
alter table public.vault_ledger_entries enable row level security;
alter table public.vault_statement_entries enable row level security;
alter table public.vault_payment_intents enable row level security;
alter table public.vault_withdrawals enable row level security;
alter table public.vault_tables enable row level security;
alter table public.vault_table_stakes enable row level security;
alter table public.vault_audit_log enable row level security;
alter table public.vault_rate_limits enable row level security;

do $$
declare
    relation text;
begin
    foreach relation in array array[
        'vault_config', 'vault_compliance_profiles', 'vault_accounts',
        'vault_ledger_transactions', 'vault_ledger_entries',
        'vault_statement_entries', 'vault_payment_intents',
        'vault_withdrawals', 'vault_tables', 'vault_table_stakes',
        'vault_audit_log', 'vault_rate_limits'
    ]
    loop
        execute format('revoke all on table public.%I from anon, authenticated', relation);
        execute format('grant select on table public.%I to authenticated', relation);
        execute format('grant all on table public.%I to service_role', relation);
    end loop;
end;
$$;

revoke select on table public.vault_config from authenticated;
grant select (id, sandbox_mode, deposit_min_cents, deposit_max_cents,
              daily_deposit_limit_cents, withdrawal_min_cents,
              withdrawal_fee_flat_cents, withdrawal_fee_basis_points)
    on table public.vault_config to authenticated;

drop policy if exists "vault_config_readable" on public.vault_config;
create policy "vault_config_readable"
    on public.vault_config for select to authenticated using (true);

drop policy if exists "vault_compliance_select_own" on public.vault_compliance_profiles;
create policy "vault_compliance_select_own"
    on public.vault_compliance_profiles for select to authenticated
    using (auth.uid() = user_id);

drop policy if exists "vault_accounts_select_own" on public.vault_accounts;
create policy "vault_accounts_select_own"
    on public.vault_accounts for select to authenticated
    using (auth.uid() = owner_user_id);

drop policy if exists "vault_ledger_transactions_select_own" on public.vault_ledger_transactions;
create policy "vault_ledger_transactions_select_own"
    on public.vault_ledger_transactions for select to authenticated
    using (auth.uid() = user_id);

drop policy if exists "vault_ledger_entries_select_own" on public.vault_ledger_entries;
create policy "vault_ledger_entries_select_own"
    on public.vault_ledger_entries for select to authenticated
    using (
        exists (
            select 1 from public.vault_accounts a
            where a.id = account_id and a.owner_user_id = auth.uid()
        )
    );

drop policy if exists "vault_statement_select_own" on public.vault_statement_entries;
create policy "vault_statement_select_own"
    on public.vault_statement_entries for select to authenticated
    using (auth.uid() = user_id);

drop policy if exists "vault_payment_intents_select_own" on public.vault_payment_intents;
create policy "vault_payment_intents_select_own"
    on public.vault_payment_intents for select to authenticated
    using (auth.uid() = user_id);

drop policy if exists "vault_withdrawals_select_own" on public.vault_withdrawals;
create policy "vault_withdrawals_select_own"
    on public.vault_withdrawals for select to authenticated
    using (auth.uid() = user_id);

drop policy if exists "vault_audit_select_own" on public.vault_audit_log;
create policy "vault_audit_select_own"
    on public.vault_audit_log for select to authenticated
    using (auth.uid() = user_id);

drop policy if exists "vault_rate_limits_select_own" on public.vault_rate_limits;
create policy "vault_rate_limits_select_own"
    on public.vault_rate_limits for select to authenticated
    using (auth.uid() = user_id);

-- A table row is readable by anyone seated at it, so the buy-in range can be
-- shown before a player sits. It carries no balances.
drop policy if exists "vault_tables_select_participant" on public.vault_tables;
create policy "vault_tables_select_participant"
    on public.vault_tables for select to authenticated
    using (
        auth.uid() = host_user_id
        or exists (
            select 1 from public.vault_table_stakes s
            where s.invite_code = vault_tables.invite_code and s.user_id = auth.uid()
        )
    );

-- Stakes hold a player's buy-in total, which is private. Direct reads are
-- limited to your own row; other seats' chips come from `vault_table_chips`,
-- which returns the chip count and nothing else.
drop policy if exists "vault_table_stakes_select_own" on public.vault_table_stakes;
create policy "vault_table_stakes_select_own"
    on public.vault_table_stakes for select to authenticated
    using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

create or replace function public.vault_reference_code(p_prefix text)
returns text
language sql
volatile
as $$
    select upper(p_prefix) || '-' || to_char(now(), 'YYYYMMDD') || '-' ||
           upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
$$;

create or replace function public.vault_require_user()
returns uuid
language plpgsql
stable
as $$
declare
    uid uuid := auth.uid();
begin
    if uid is null then
        raise exception 'vault: not signed in' using errcode = '28000';
    end if;
    return uid;
end;
$$;

create or replace function public.vault_log(
    p_user_id uuid,
    p_action text,
    p_outcome text default 'ok',
    p_amount_cents bigint default null,
    p_reference_code text default null,
    p_table_invite_code text default null,
    p_detail jsonb default '{}'::jsonb
)
returns void
language sql
volatile
security definer
set search_path = public
as $$
    insert into public.vault_audit_log (
        user_id, actor_user_id, action, outcome, amount_cents,
        reference_code, table_invite_code, detail
    )
    values (
        p_user_id, auth.uid(), p_action, p_outcome, p_amount_cents,
        p_reference_code, p_table_invite_code, coalesce(p_detail, '{}'::jsonb)
    );
$$;

create or replace function public.vault_touch_rate_limit(
    p_user_id uuid,
    p_bucket text,
    p_max_hits integer,
    p_window interval
)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    current_hits integer;
begin
    insert into public.vault_rate_limits (user_id, bucket, window_started_at, hits)
    values (p_user_id, p_bucket, now(), 1)
    on conflict (user_id, bucket) do update
        set hits = case
                when public.vault_rate_limits.window_started_at < now() - p_window then 1
                else public.vault_rate_limits.hits + 1
            end,
            window_started_at = case
                when public.vault_rate_limits.window_started_at < now() - p_window then now()
                else public.vault_rate_limits.window_started_at
            end
    returning hits into current_hits;

    if current_hits > p_max_hits then
        raise exception 'vault: too many % requests, try again shortly', p_bucket
            using errcode = '53400';
    end if;
end;
$$;

create or replace function public.vault_ensure_compliance_profile(p_user_id uuid)
returns public.vault_compliance_profiles
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    profile public.vault_compliance_profiles;
begin
    insert into public.vault_compliance_profiles (user_id)
    values (p_user_id)
    on conflict (user_id) do nothing;

    select * into profile from public.vault_compliance_profiles where user_id = p_user_id;
    return profile;
end;
$$;

create or replace function public.vault_account(
    p_owner uuid,
    p_kind text,
    p_currency text default 'USD',
    p_table_invite_code text default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    account_id uuid;
begin
    if p_owner is null then
        select id into account_id
        from public.vault_accounts
        where owner_user_id is null and kind = p_kind and currency_code = p_currency;
    else
        select id into account_id
        from public.vault_accounts
        where owner_user_id = p_owner
          and kind = p_kind
          and coalesce(table_invite_code, '') = coalesce(p_table_invite_code, '');
    end if;

    if account_id is not null then
        return account_id;
    end if;

    insert into public.vault_accounts (owner_user_id, kind, currency_code, table_invite_code)
    values (p_owner, p_kind, p_currency, p_table_invite_code)
    on conflict do nothing
    returning id into account_id;

    if account_id is null then
        return public.vault_account(p_owner, p_kind, p_currency, p_table_invite_code);
    end if;

    return account_id;
end;
$$;

-- Posts one balanced transaction. `p_moves` is a jsonb array of
-- {"account_id": uuid, "amount_cents": bigint} whose amounts must sum to zero.
-- Accounts are locked in a stable order so two concurrent postings touching the
-- same pair of accounts cannot deadlock, and a player account that would be
-- driven below zero aborts the whole transaction.
create or replace function public.vault_post_transaction(
    p_user_id uuid,
    p_kind text,
    p_moves jsonb,
    p_idempotency_key text default null,
    p_table_invite_code text default null,
    p_metadata jsonb default '{}'::jsonb
)
returns public.vault_ledger_transactions
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    existing public.vault_ledger_transactions;
    posted public.vault_ledger_transactions;
    move jsonb;
    total bigint := 0;
    locked_id uuid;
    next_balance bigint;
    is_player_account boolean;
begin
    if p_idempotency_key is not null then
        select * into existing
        from public.vault_ledger_transactions
        where user_id = p_user_id and idempotency_key = p_idempotency_key;

        if found then
            return existing;
        end if;
    end if;

    -- A move of zero is dropped rather than written: an entry always represents
    -- money that actually moved. A fee of nothing is simply no fee.
    p_moves := coalesce(
        (
            select jsonb_agg(value)
            from jsonb_array_elements(p_moves)
            where (value->>'amount_cents')::bigint <> 0
        ),
        '[]'::jsonb
    );

    if jsonb_array_length(p_moves) = 0 then
        raise exception 'vault: nothing to post' using errcode = '23514';
    end if;

    for move in select value from jsonb_array_elements(p_moves)
    loop
        total := total + (move->>'amount_cents')::bigint;
    end loop;

    if total <> 0 then
        raise exception 'vault: entries do not balance (off by % cents)', total
            using errcode = '23514';
    end if;

    insert into public.vault_ledger_transactions (
        reference_code, user_id, kind, idempotency_key, table_invite_code, metadata
    )
    values (
        public.vault_reference_code(case p_kind
            when 'deposit' then 'DEP'
            when 'withdrawal_request' then 'WDR'
            when 'withdrawal_completed' then 'WDC'
            else 'TXN'
        end),
        p_user_id, p_kind, p_idempotency_key, p_table_invite_code,
        coalesce(p_metadata, '{}'::jsonb)
    )
    returning * into posted;

    for locked_id in
        select (value->>'account_id')::uuid
        from jsonb_array_elements(p_moves)
        order by 1
    loop
        perform 1 from public.vault_accounts where id = locked_id for update;
    end loop;

    for move in select value from jsonb_array_elements(p_moves)
    loop
        insert into public.vault_ledger_entries (transaction_id, account_id, amount_cents)
        values (posted.id, (move->>'account_id')::uuid, (move->>'amount_cents')::bigint);

        update public.vault_accounts
        set balance_cents = balance_cents + (move->>'amount_cents')::bigint,
            updated_at = now()
        where id = (move->>'account_id')::uuid
        returning balance_cents, owner_user_id is not null
        into next_balance, is_player_account;

        if is_player_account and next_balance < 0 then
            raise exception 'vault: not enough money' using errcode = '23514';
        end if;
    end loop;

    return posted;
exception
    when unique_violation then
        if p_idempotency_key is null then
            raise;
        end if;
        select * into existing
        from public.vault_ledger_transactions
        where user_id = p_user_id and idempotency_key = p_idempotency_key;
        if found then
            return existing;
        end if;
        raise;
end;
$$;

create or replace function public.vault_add_statement(
    p_user_id uuid,
    p_kind text,
    p_status text,
    p_amount_cents bigint,
    p_currency text,
    p_ledger_transaction_id uuid default null,
    p_payment_intent_id uuid default null,
    p_withdrawal_id uuid default null,
    p_table_invite_code text default null,
    p_detail text default null
)
returns public.vault_statement_entries
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    row_out public.vault_statement_entries;
begin
    insert into public.vault_statement_entries (
        user_id, reference_code, kind, status, amount_cents, currency_code,
        ledger_transaction_id, payment_intent_id, withdrawal_id,
        table_invite_code, is_demo, detail
    )
    values (
        p_user_id, public.vault_reference_code('PM'), p_kind, p_status,
        p_amount_cents, p_currency, p_ledger_transaction_id, p_payment_intent_id,
        p_withdrawal_id, p_table_invite_code, public.vault_is_sandbox(), p_detail
    )
    returning * into row_out;

    return row_out;
end;
$$;

-- Raises unless the player is allowed to move money right now. `p_activity` is
-- 'deposit', 'play' or 'withdrawal'.
create or replace function public.vault_assert_allowed(
    p_user_id uuid,
    p_activity text,
    p_amount_cents bigint default 0
)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    profile public.vault_compliance_profiles;
    config public.vault_config;
    deposited_today bigint;
    lost_today bigint;
    effective_deposit_limit bigint;
begin
    profile := public.vault_ensure_compliance_profile(p_user_id);
    select * into config from public.vault_config where id;

    if profile.account_status = 'suspended' then
        raise exception 'vault: this account is suspended' using errcode = '42501';
    end if;

    if profile.account_status = 'closed' then
        raise exception 'vault: this account is closed' using errcode = '42501';
    end if;

    if profile.account_status = 'restricted' and p_activity <> 'withdrawal' then
        raise exception 'vault: this account is restricted (%)',
            coalesce(profile.restriction_reason, 'contact support')
            using errcode = '42501';
    end if;

    if profile.jurisdiction_status = 'blocked' then
        raise exception 'vault: real-money play is not available in your location'
            using errcode = '42501';
    end if;

    if profile.sanctions_status = 'hit' then
        raise exception 'vault: this account is under review' using errcode = '42501';
    end if;

    if profile.self_excluded_until is not null
       and profile.self_excluded_until > now()
       and p_activity in ('deposit', 'play') then
        raise exception 'vault: self-exclusion is active until %',
            to_char(profile.self_excluded_until, 'YYYY-MM-DD')
            using errcode = '42501';
    end if;

    if p_activity = 'deposit' then
        effective_deposit_limit := least(
            coalesce(profile.daily_deposit_limit_cents, config.daily_deposit_limit_cents),
            config.daily_deposit_limit_cents
        );

        select coalesce(sum(amount_cents), 0) into deposited_today
        from public.vault_payment_intents
        where user_id = p_user_id
          and status = 'succeeded'
          and created_at >= date_trunc('day', now());

        if deposited_today + p_amount_cents > effective_deposit_limit then
            raise exception 'vault: that would pass your daily deposit limit'
                using errcode = '53400';
        end if;
    end if;

    if p_activity = 'play' and profile.daily_loss_limit_cents is not null then
        select coalesce(-sum(amount_cents), 0) into lost_today
        from public.vault_statement_entries
        where user_id = p_user_id
          and kind in ('table_loss', 'table_winnings')
          and status = 'completed'
          and created_at >= date_trunc('day', now());

        if lost_today >= profile.daily_loss_limit_cents then
            raise exception 'vault: you have reached your daily loss limit'
                using errcode = '53400';
        end if;
    end if;

    if p_activity = 'withdrawal' then
        if not public.vault_is_sandbox() and profile.identity_status <> 'verified' then
            raise exception 'vault: verify your identity before cashing out'
                using errcode = '42501';
        end if;
        if not public.vault_is_sandbox() and profile.payout_method_status <> 'verified' then
            raise exception 'vault: add a verified payout method before cashing out'
                using errcode = '42501';
        end if;
        if profile.sanctions_status = 'review' then
            raise exception 'vault: this cash-out is being reviewed' using errcode = '42501';
        end if;
    end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Reading the vault
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
    available bigint;
    in_play bigint;
    pending_withdrawal bigint;
    pending_deposit bigint;
    profile public.vault_compliance_profiles;
    config public.vault_config;
begin
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
        'currency_code', 'USD',
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

create or replace function public.vault_open(p_currency text default 'USD')
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    uid uuid := public.vault_require_user();
begin
    perform public.vault_ensure_compliance_profile(uid);
    perform public.vault_account(uid, 'available', p_currency);
    perform public.vault_account(uid, 'pending_withdrawal', p_currency);
    perform public.vault_account(null, 'psp_clearing', p_currency);
    perform public.vault_account(null, 'payout_clearing', p_currency);
    perform public.vault_account(null, 'fees', p_currency);
    return public.vault_summary();
end;
$$;

create or replace function public.vault_statement(
    p_limit integer default 50,
    p_before timestamptz default null
)
returns setof public.vault_statement_entries
language sql
stable
security definer
set search_path = public
as $$
    select *
    from public.vault_statement_entries
    where user_id = public.vault_require_user()
      and (p_before is null or created_at < p_before)
    order by created_at desc
    limit least(greatest(coalesce(p_limit, 50), 1), 200);
$$;

-- The one financial fact other players may read: chips in play at a table the
-- caller is also seated at. No buy-in totals, no vault balances, no history.
create or replace function public.vault_table_chips(p_invite_code text)
returns table (player_key text, display_name text, in_play_cents bigint)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    uid uuid := public.vault_require_user();
    code text := upper(trim(p_invite_code));
begin
    if not exists (
        select 1 from public.vault_table_stakes s
        where s.invite_code = code and s.user_id = uid
    ) and not exists (
        select 1 from public.vault_tables t
        where t.invite_code = code and t.host_user_id = uid
    ) then
        raise exception 'vault: you are not at that table' using errcode = '42501';
    end if;

    return query
        select s.player_key, s.display_name, s.in_play_cents
        from public.vault_table_stakes s
        where s.invite_code = code and s.status = 'seated'
        order by s.seated_at;
end;
$$;

-- ---------------------------------------------------------------------------
-- Deposits
-- ---------------------------------------------------------------------------

create or replace function public.vault_create_deposit_intent(
    p_amount_cents bigint,
    p_idempotency_key text,
    p_purpose text default 'vault_deposit',
    p_table_invite_code text default null,
    p_provider text default 'mock_apple_pay',
    p_currency text default 'USD'
)
returns public.vault_payment_intents
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    uid uuid := public.vault_require_user();
    config public.vault_config;
    intent public.vault_payment_intents;
begin
    select * into intent
    from public.vault_payment_intents
    where user_id = uid and idempotency_key = p_idempotency_key;

    if found then
        return intent;
    end if;

    perform public.vault_touch_rate_limit(uid, 'deposit_intent', 20, interval '5 minutes');

    select * into config from public.vault_config where id;

    if p_amount_cents < config.deposit_min_cents then
        raise exception 'vault: the smallest deposit is % cents', config.deposit_min_cents
            using errcode = '23514';
    end if;

    if p_amount_cents > config.deposit_max_cents then
        raise exception 'vault: the largest deposit is % cents', config.deposit_max_cents
            using errcode = '23514';
    end if;

    perform public.vault_assert_allowed(uid, 'deposit', p_amount_cents);
    perform public.vault_open(p_currency);

    insert into public.vault_payment_intents (
        user_id, reference_code, provider, purpose, amount_cents, currency_code,
        table_invite_code, idempotency_key, is_demo
    )
    values (
        uid, public.vault_reference_code('PI'), p_provider, p_purpose,
        p_amount_cents, p_currency, upper(nullif(trim(coalesce(p_table_invite_code, '')), '')),
        p_idempotency_key, public.vault_is_sandbox()
    )
    returning * into intent;

    if p_purpose = 'vault_deposit' then
        perform public.vault_add_statement(
            uid, 'deposit', 'pending', p_amount_cents, p_currency,
            null, intent.id, null, null, 'Awaiting payment confirmation'
        );
    end if;

    perform public.vault_log(uid, 'deposit_intent_created', 'ok', p_amount_cents,
                             intent.reference_code, intent.table_invite_code);
    return intent;
end;
$$;

-- Settles a deposit. This is the only path that turns an intent into money and
-- it never runs on the word of the app: in production it is called by the
-- webhook handler as `service_role` after the provider signature is verified.
-- `vault_sandbox_confirm_deposit` below is the demo stand-in for that webhook.
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

    -- Replayed webhook for an intent that is already resolved: return as-is.
    if intent.status in ('succeeded', 'failed', 'canceled', 'reversed') then
        return intent;
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

-- Demo only. Stands in for the provider webhook while `sandbox_mode` is on so
-- the flow can be exercised end to end without a real payment. Even here the
-- app never says how much arrived — the amount comes from the stored intent.
create or replace function public.vault_sandbox_confirm_deposit(
    p_intent_id uuid,
    p_outcome text default 'succeeded'
)
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
    if not public.vault_is_sandbox() then
        raise exception 'vault: sandbox confirmation is switched off' using errcode = '42501';
    end if;

    select * into intent from public.vault_payment_intents where id = p_intent_id;
    if not found or intent.user_id <> uid then
        raise exception 'vault: unknown payment' using errcode = 'P0002';
    end if;

    perform public.vault_touch_rate_limit(uid, 'sandbox_confirm', 30, interval '5 minutes');

    return public.vault_settle_deposit_intent(
        p_intent_id,
        p_outcome,
        'sandbox_' || p_intent_id::text,
        case when p_outcome = 'succeeded' then null else 'Simulated failure' end
    );
end;
$$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

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
    row_out public.vault_tables;
begin
    if code = '' then
        raise exception 'vault: a table needs a code' using errcode = '23514';
    end if;

    insert into public.vault_tables (
        invite_code, host_user_id, currency_code,
        min_buy_in_cents, max_buy_in_cents, is_demo
    )
    values (code, uid, p_currency, p_min_buy_in_cents, p_max_buy_in_cents,
            public.vault_is_sandbox())
    on conflict (invite_code) do update
        set min_buy_in_cents = excluded.min_buy_in_cents,
            max_buy_in_cents = excluded.max_buy_in_cents,
            currency_code = excluded.currency_code,
            updated_at = now()
        where public.vault_tables.host_user_id = uid
    returning * into row_out;

    if row_out.invite_code is null then
        select * into row_out from public.vault_tables where invite_code = code;
    end if;

    return row_out;
end;
$$;

-- Moves a verified buy-in into play. `p_source` is 'vault' or 'apple_pay'. An
-- Apple Pay buy-in must name an intent this backend has already settled; the
-- app cannot assert that a payment happened.
create or replace function public.vault_table_buy_in(
    p_invite_code text,
    p_amount_cents bigint,
    p_source text,
    p_idempotency_key text,
    p_player_key text,
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
    tbl public.vault_tables;
    intent public.vault_payment_intents;
    posted public.vault_ledger_transactions;
    source_account uuid;
    in_play uuid;
    stake public.vault_table_stakes;
begin
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
        jsonb_build_object('source', p_source, 'player_key', p_player_key)
    );

    insert into public.vault_table_stakes (
        invite_code, user_id, player_key, display_name,
        total_bought_in_cents, in_play_cents, status
    )
    values (code, uid, p_player_key, p_display_name, p_amount_cents, p_amount_cents, 'seated')
    on conflict (invite_code, user_id) do update
        set player_key = excluded.player_key,
            display_name = excluded.display_name,
            status = 'seated',
            left_at = null
    returning * into stake;

    -- Refresh the cached chip count from the ledger rather than adding to it, so
    -- a replayed request cannot inflate the seat.
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

    -- A buy-in sent twice reuses the transaction already on file, so the
    -- statement is only written the first time round.
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
        'in_play_cents', stake.in_play_cents,
        'total_bought_in_cents', stake.total_bought_in_cents
    );
end;
$$;

-- Records the result of a hand. Only the host of the table may call it, the
-- moves must be zero-sum across the seats, and no seat may be driven below
-- zero. The idempotency key is the hand id, so a hand posted twice is ignored.
create or replace function public.vault_record_hand(
    p_invite_code text,
    p_hand_id text,
    p_deltas jsonb
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
    item jsonb;
    moves jsonb := '[]'::jsonb;
    total bigint := 0;
    stake_user uuid;
    delta bigint;
    account uuid;
    posted public.vault_ledger_transactions;
begin
    select * into tbl from public.vault_tables where invite_code = code for update;
    if not found then
        raise exception 'vault: unknown table' using errcode = 'P0002';
    end if;
    if tbl.host_user_id <> uid then
        raise exception 'vault: only the host records a hand' using errcode = '42501';
    end if;

    for item in select value from jsonb_array_elements(p_deltas)
    loop
        select s.user_id into stake_user
        from public.vault_table_stakes s
        where s.invite_code = code and s.player_key = item->>'player_key';

        if stake_user is null then
            raise exception 'vault: % is not seated here', item->>'player_key'
                using errcode = 'P0002';
        end if;

        delta := (item->>'delta_cents')::bigint;
        if delta = 0 then
            continue;
        end if;

        account := public.vault_account(stake_user, 'in_play', tbl.currency_code, code);
        moves := moves || jsonb_build_array(
            jsonb_build_object('account_id', account, 'amount_cents', delta)
        );
        total := total + delta;
    end loop;

    if total <> 0 then
        raise exception 'vault: a hand has to be zero-sum (off by % cents)', total
            using errcode = '23514';
    end if;

    if jsonb_array_length(moves) = 0 then
        return jsonb_build_object('status', 'noop');
    end if;

    posted := public.vault_post_transaction(
        uid, 'table_hand', moves, 'hand:' || code || ':' || p_hand_id, code,
        jsonb_build_object('hand_id', p_hand_id)
    );

    -- A hand sent twice returns the transaction already on file. Nothing moved
    -- the second time, so nothing new belongs on anyone's statement either.
    if exists (
        select 1 from public.vault_statement_entries
        where ledger_transaction_id = posted.id
    ) then
        return jsonb_build_object('reference_code', posted.reference_code, 'status', 'replayed');
    end if;

    for item in select value from jsonb_array_elements(p_deltas)
    loop
        select s.user_id into stake_user
        from public.vault_table_stakes s
        where s.invite_code = code and s.player_key = item->>'player_key';

        delta := (item->>'delta_cents')::bigint;
        if stake_user is null or delta = 0 then
            continue;
        end if;

        account := public.vault_account(stake_user, 'in_play', tbl.currency_code, code);

        update public.vault_table_stakes
        set in_play_cents = (select balance_cents from public.vault_accounts where id = account)
        where invite_code = code and user_id = stake_user;

        perform public.vault_add_statement(
            stake_user,
            case when delta > 0 then 'table_winnings' else 'table_loss' end,
            'completed', 0, tbl.currency_code, posted.id, null, null, code,
            case when delta > 0 then 'Won at the table' else 'Lost at the table' end
        );
    end loop;

    perform public.vault_log(uid, 'table_hand', 'ok', null, posted.reference_code, code,
                             jsonb_build_object('hand_id', p_hand_id));

    return jsonb_build_object('reference_code', posted.reference_code, 'status', 'posted');
end;
$$;

-- Returns whatever the backend says a seat is holding to that player's vault.
-- The amount is read from the ledger, never from the app.
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

    -- Already cashed off this table: hand back the same figures rather than
    -- running the settlement again.
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

-- ---------------------------------------------------------------------------
-- Withdrawals
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
begin
    select * into withdrawal
    from public.vault_withdrawals
    where user_id = uid and idempotency_key = p_idempotency_key;

    if found then
        return withdrawal;
    end if;

    perform public.vault_touch_rate_limit(uid, 'withdrawal', 10, interval '10 minutes');
    perform public.vault_assert_allowed(uid, 'withdrawal', p_amount_cents);

    select * into config from public.vault_config where id;

    if p_amount_cents < config.withdrawal_min_cents then
        raise exception 'vault: the smallest cash-out is % cents', config.withdrawal_min_cents
            using errcode = '23514';
    end if;

    perform public.vault_open(p_currency);
    available := public.vault_account(uid, 'available', p_currency);
    reserved := public.vault_account(uid, 'pending_withdrawal', p_currency);

    -- Money in play, already reserved for another cash-out, or still pending as
    -- a deposit is not in this balance, so none of it can be withdrawn.
    select balance_cents into available_cents
    from public.vault_accounts where id = available for update;

    if p_amount_cents > available_cents then
        raise exception 'vault: you can cash out at most % cents right now', available_cents
            using errcode = '23514';
    end if;

    fee := config.withdrawal_fee_flat_cents
         + (p_amount_cents * config.withdrawal_fee_basis_points) / 10000;

    if fee >= p_amount_cents then
        raise exception 'vault: that is less than the cash-out fee' using errcode = '23514';
    end if;

    -- Reserving the money is what stops it being spent or withdrawn twice.
    posted := public.vault_post_transaction(
        uid, 'withdrawal_request',
        jsonb_build_array(
            jsonb_build_object('account_id', available, 'amount_cents', -p_amount_cents),
            jsonb_build_object('account_id', reserved, 'amount_cents', p_amount_cents)
        ),
        p_idempotency_key, null,
        jsonb_build_object('fee_cents', fee)
    );

    insert into public.vault_withdrawals (
        user_id, reference_code, amount_cents, fee_cents, net_cents,
        currency_code, idempotency_key, is_demo
    )
    values (
        uid, public.vault_reference_code('CO'), p_amount_cents, fee,
        p_amount_cents - fee, p_currency, p_idempotency_key, public.vault_is_sandbox()
    )
    returning * into withdrawal;

    perform public.vault_add_statement(
        uid, 'withdrawal_request', 'pending', 0, p_currency,
        posted.id, null, withdrawal.id, null, 'Cash-out requested'
    );

    perform public.vault_log(uid, 'withdrawal_requested', 'ok', p_amount_cents,
                             withdrawal.reference_code);
    return withdrawal;
end;
$$;

-- Resolves a cash-out. Operator or payout-provider webhook only: an ordinary
-- signed-in player cannot mark their own withdrawal paid.
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
begin
    -- Reachable by `service_role` (no `auth.uid()`) or by the sandbox payout
    -- simulator, which sets the guard below for the length of one statement. A
    -- signed-in player calling this directly is turned away.
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

    reserved := public.vault_account(withdrawal.user_id, 'pending_withdrawal', withdrawal.currency_code);
    available := public.vault_account(withdrawal.user_id, 'available', withdrawal.currency_code);
    payout := public.vault_account(null, 'payout_clearing', withdrawal.currency_code);
    fees := public.vault_account(null, 'fees', withdrawal.currency_code);

    if p_outcome = 'completed' then
        posted := public.vault_post_transaction(
            withdrawal.user_id, 'withdrawal_completed',
            jsonb_build_array(
                jsonb_build_object('account_id', reserved, 'amount_cents', -withdrawal.amount_cents),
                jsonb_build_object('account_id', payout, 'amount_cents', withdrawal.net_cents),
                jsonb_build_object('account_id', fees, 'amount_cents', withdrawal.fee_cents)
            ),
            'withdrawal_complete:' || withdrawal.id::text, null,
            jsonb_build_object('transfer', p_provider_transfer_id)
        );

        perform public.vault_add_statement(
            withdrawal.user_id, 'withdrawal_completed', 'completed',
            -withdrawal.amount_cents, withdrawal.currency_code,
            posted.id, null, withdrawal.id, null, 'Paid out'
        );
    else
        -- Rejected, canceled or failed: the reserved money goes back.
        posted := public.vault_post_transaction(
            withdrawal.user_id, 'withdrawal_' || p_outcome,
            jsonb_build_array(
                jsonb_build_object('account_id', reserved, 'amount_cents', -withdrawal.amount_cents),
                jsonb_build_object('account_id', available, 'amount_cents', withdrawal.amount_cents)
            ),
            'withdrawal_' || p_outcome || ':' || withdrawal.id::text, null,
            jsonb_build_object('reason', p_failure_reason)
        );

        perform public.vault_add_statement(
            withdrawal.user_id, 'withdrawal_' || p_outcome,
            case p_outcome when 'rejected' then 'rejected'
                           when 'canceled' then 'canceled'
                           else 'failed' end,
            0, withdrawal.currency_code, posted.id, null, withdrawal.id, null,
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

-- A player may cancel their own cash-out while it is still pending. The money
-- goes straight back to available.
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

    reserved := public.vault_account(uid, 'pending_withdrawal', withdrawal.currency_code);
    available := public.vault_account(uid, 'available', withdrawal.currency_code);

    posted := public.vault_post_transaction(
        uid, 'withdrawal_canceled',
        jsonb_build_array(
            jsonb_build_object('account_id', reserved, 'amount_cents', -withdrawal.amount_cents),
            jsonb_build_object('account_id', available, 'amount_cents', withdrawal.amount_cents)
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
        uid, 'withdrawal_canceled', 'canceled', 0, withdrawal.currency_code,
        posted.id, null, withdrawal.id, null, 'You canceled this cash-out'
    );

    perform public.vault_log(uid, 'withdrawal_canceled', 'ok',
                             withdrawal.amount_cents, withdrawal.reference_code);
    return withdrawal;
end;
$$;

-- Demo only: walks a pending cash-out through the payout provider so the
-- pending → completed states can be seen without a real payout rail.
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
        raise exception 'vault: sandbox payouts are switched off' using errcode = '42501';
    end if;

    select * into withdrawal from public.vault_withdrawals where id = p_withdrawal_id;
    if not found or withdrawal.user_id <> uid then
        raise exception 'vault: unknown cash-out' using errcode = 'P0002';
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

-- ---------------------------------------------------------------------------
-- Reconciliation
-- ---------------------------------------------------------------------------
-- Two checks an operator can run at any time: every account balance must equal
-- the sum of its entries, and every transaction's entries must sum to zero.

create or replace function public.vault_reconcile_accounts()
returns table (
    account_id uuid,
    owner_user_id uuid,
    kind text,
    stored_cents bigint,
    ledger_cents bigint,
    drift_cents bigint
)
language sql
stable
security definer
set search_path = public
as $$
    select a.id,
           a.owner_user_id,
           a.kind,
           a.balance_cents,
           coalesce(sum(e.amount_cents), 0),
           a.balance_cents - coalesce(sum(e.amount_cents), 0)
    from public.vault_accounts a
    left join public.vault_ledger_entries e on e.account_id = a.id
    group by a.id, a.owner_user_id, a.kind, a.balance_cents
    having a.balance_cents <> coalesce(sum(e.amount_cents), 0);
$$;

create or replace function public.vault_reconcile_transactions()
returns table (transaction_id uuid, reference_code text, drift_cents bigint)
language sql
stable
security definer
set search_path = public
as $$
    select t.id, t.reference_code, sum(e.amount_cents)
    from public.vault_ledger_transactions t
    join public.vault_ledger_entries e on e.transaction_id = t.id
    group by t.id, t.reference_code
    having sum(e.amount_cents) <> 0;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
-- Only the read and player-initiated functions are reachable from the app.
-- Settlement of deposits and payouts stays with `service_role`.

do $$
declare
    signature text;
begin
    foreach signature in array array[
        'public.vault_open(text)',
        'public.vault_summary()',
        'public.vault_statement(integer, timestamptz)',
        'public.vault_table_chips(text)',
        'public.vault_create_deposit_intent(bigint, text, text, text, text, text)',
        'public.vault_sandbox_confirm_deposit(uuid, text)',
        'public.vault_register_table(text, bigint, bigint, text)',
        'public.vault_table_buy_in(text, bigint, text, text, text, text, uuid)',
        'public.vault_record_hand(text, text, jsonb)',
        'public.vault_leave_table(text, text)',
        'public.vault_request_withdrawal(bigint, text, text)',
        'public.vault_cancel_withdrawal(uuid)',
        'public.vault_sandbox_resolve_withdrawal(uuid, text)'
    ]
    loop
        execute format('revoke all on function %s from public, anon', signature);
        execute format('grant execute on function %s to authenticated', signature);
    end loop;

    foreach signature in array array[
        'public.vault_settle_deposit_intent(uuid, text, text, text)',
        'public.vault_resolve_withdrawal(uuid, text, text, text)',
        'public.vault_reconcile_accounts()',
        'public.vault_reconcile_transactions()',
        'public.vault_post_transaction(uuid, text, jsonb, text, text, jsonb)',
        'public.vault_add_statement(uuid, text, text, bigint, text, uuid, uuid, uuid, text, text)',
        'public.vault_account(uuid, text, text, text)',
        'public.vault_assert_allowed(uuid, text, bigint)',
        'public.vault_ensure_compliance_profile(uuid)',
        'public.vault_touch_rate_limit(uuid, text, integer, interval)',
        'public.vault_log(uuid, text, text, bigint, text, text, jsonb)'
    ]
    loop
        execute format('revoke all on function %s from public, anon, authenticated', signature);
        execute format('grant execute on function %s to service_role', signature);
    end loop;
end;
$$;

notify pgrst, 'reload schema';
