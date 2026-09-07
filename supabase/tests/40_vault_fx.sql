\set ON_ERROR_STOP on
\pset pager off

insert into auth.users (id, email) values
    ('44444444-4444-4444-4444-444444444444', 'usd-player@example.com');

select set_config('test.uid', '44444444-4444-4444-4444-444444444444', false);

\echo '=== FX1. published rates ==='
select public.test_assert(public.vault_convert_cents(10000, 'USD', 'GBP') = 7900,
    '$100 must convert to £79');
select public.test_assert(public.vault_convert_cents(7900, 'GBP', 'USD') = 10000,
    '£79 must convert back to $100');
select public.test_assert(public.vault_convert_cents(2000, 'USD', 'USD') = 2000,
    'same-currency conversion is a no-op');

\echo '=== FX2. buy in USD, sit in GBP ==='
select public.vault_open('USD');
select id as dep from public.vault_create_deposit_intent(10000, 'fx-dep-1') \gset
select status from public.vault_sandbox_confirm_deposit(:'dep');

insert into public.open_tables (
    id, invite_code, host_user_id, host_display_name, host_player_key,
    session_currency_code
) values (
    'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
    'FXGBP1',
    '44444444-4444-4444-4444-444444444444',
    'USD Player',
    '44444444-4444-4444-4444-444444444444',
    'GBP'
);

select currency_code from public.vault_register_table('FXGBP1', 1000, 8000, 'USD');
select public.test_assert(
    (select currency_code from public.vault_tables where invite_code = 'FXGBP1') = 'GBP',
    'GBP table must settle in GBP'
);

select public.vault_table_buy_in('FXGBP1', 2000, 'vault', 'fx-buy-1', 'USD Player');

select public.test_assert(
    (public.vault_summary()->>'available_cents')::bigint
        = 10000 - public.vault_convert_cents(2000, 'GBP', 'USD')
    and (public.vault_summary()->>'in_play_cents')::bigint
        = public.vault_convert_cents(2000, 'GBP', 'USD')
    and (public.vault_summary()->>'total_cents')::bigint = 10000,
    'USD buy-in onto a GBP table must convert, then transfer'
);

select public.test_assert(
    (select in_play_cents from public.vault_table_stakes
     where invite_code = 'FXGBP1') = 2000,
    'the seat must hold £20 of table chips'
);

\echo '=== FX3. leaving converts GBP chips back into the USD wallet ==='
select public.vault_leave_table('FXGBP1', 'fx-leave-1');
select public.test_assert(
    (public.vault_summary()->>'available_cents')::bigint = 10000
    and (public.vault_summary()->>'in_play_cents')::bigint = 0,
    'cashing off a GBP table must return the converted USD'
);

\echo '=== FX4. withdraw in GBP from a USD vault, then transfer ==='
select id as w_id from public.vault_request_withdrawal(7900, 'fx-cash-1', 'GBP') \gset

select public.test_assert(
    (select currency_code from public.vault_withdrawals where id = :'w_id') = 'GBP'
    and (select source_amount_cents from public.vault_withdrawals where id = :'w_id') = 10000
    and (select source_currency_code from public.vault_withdrawals where id = :'w_id') = 'USD'
    and (public.vault_summary()->>'available_cents')::bigint = 0
    and (public.vault_summary()->>'pending_withdrawal_cents')::bigint = 10000,
    'a £79 cash-out must reserve $100'
);

select status, net_cents from public.vault_sandbox_resolve_withdrawal(:'w_id', 'completed');
select public.test_assert(
    (public.vault_summary()->>'available_cents')::bigint = 0
    and (public.vault_summary()->>'pending_withdrawal_cents')::bigint = 0
    and (public.vault_summary()->>'total_cents')::bigint = 0,
    'the GBP payout must leave the Vault'
);

select public.test_assert(
    not exists (select 1 from public.vault_reconcile_accounts()),
    'account ledger must reconcile after FX transfers'
);
select public.test_assert(
    not exists (select 1 from public.vault_reconcile_transactions()),
    'transaction ledger must reconcile after FX transfers'
);
