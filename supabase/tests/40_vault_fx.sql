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
select public.test_assert(public.vault_convert_cents(10000, 'USD', 'EUR') = 9200,
    '$100 must convert to €92');
select public.test_assert(public.vault_convert_cents(10000, 'EUR', 'USD') = 10870,
    '€100 must convert to $108.70');
select public.test_assert(public.vault_convert_cents(2000, 'ILS', 'CAD')
        = round(2000::numeric * 1.36 / 3.72),
    'ILS to CAD must use both published rates');
select public.test_assert(public.vault_convert_cents(10000, 'USD', 'JPY') = 1570000,
    '$100 must convert to ¥15,700 in integer hundredths');
select public.test_assert(public.vault_fx_rate('AUD') = 1.51
    and public.vault_fx_rate('CAD') = 1.36
    and public.vault_fx_rate('ILS') = 3.72
    and public.vault_fx_rate('TWD') = 32.5,
    'featured and world currencies must have published rates');

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

insert into auth.users (id, email) values
    ('55555555-5555-5555-5555-555555555555', 'eur-player@example.com');

select set_config('test.uid', '55555555-5555-5555-5555-555555555555', false);

\echo '=== FX5. EUR wallet, ILS table, then CAD cash-out ==='
select public.vault_open('EUR');
select public.test_assert(
    public.vault_summary()->>'currency_code' = 'EUR',
    'a first visit must open the vault in the requested currency'
);

-- A later open in another unit must not create a second wallet.
select public.vault_open('JPY');
select public.test_assert(
    public.vault_summary()->>'currency_code' = 'EUR',
    'opening again must keep the existing wallet currency'
);

select id as eur_dep from public.vault_create_deposit_intent(
    10000, 'fx-eur-dep-1', 'vault_deposit', null, 'mock_apple_pay', 'EUR'
) \gset
select status from public.vault_sandbox_confirm_deposit(:'eur_dep');
select public.test_assert(
    (public.vault_summary()->>'available_cents')::bigint = 10000
    and public.vault_summary()->>'currency_code' = 'EUR',
    'an EUR deposit must credit the EUR wallet'
);

insert into public.open_tables (
    id, invite_code, host_user_id, host_display_name, host_player_key,
    session_currency_code
) values (
    'ffffffff-ffff-ffff-ffff-ffffffffffff',
    'FXILS1',
    '55555555-5555-5555-5555-555555555555',
    'EUR Player',
    '55555555-5555-5555-5555-555555555555',
    'ILS'
);

select currency_code from public.vault_register_table('FXILS1', 1000, 8000, 'ILS');
select public.vault_table_buy_in('FXILS1', 2000, 'vault', 'fx-ils-buy-1', 'EUR Player');

select public.test_assert(
    (select in_play_cents from public.vault_table_stakes
     where invite_code = 'FXILS1') = 2000
    and (public.vault_summary()->>'available_cents')::bigint
        = 10000 - public.vault_convert_cents(2000, 'ILS', 'EUR')
    and (public.vault_summary()->>'in_play_cents')::bigint
        = public.vault_convert_cents(2000, 'ILS', 'EUR'),
    'EUR buy-in onto an ILS table must convert, then transfer'
);

select public.vault_leave_table('FXILS1', 'fx-ils-leave-1');
select public.test_assert(
    (public.vault_summary()->>'available_cents')::bigint = 10000
    and (public.vault_summary()->>'in_play_cents')::bigint = 0,
    'leaving an ILS table must return converted EUR'
);

select id as cad_w from public.vault_request_withdrawal(2000, 'fx-cad-1', 'CAD') \gset
select public.test_assert(
    (select currency_code from public.vault_withdrawals where id = :'cad_w') = 'CAD'
    and (select source_currency_code from public.vault_withdrawals where id = :'cad_w') = 'EUR'
    and (select source_amount_cents from public.vault_withdrawals where id = :'cad_w')
        = public.vault_convert_cents(2000, 'CAD', 'EUR'),
    'a CAD cash-out from an EUR vault must reserve converted EUR'
);

select status from public.vault_sandbox_resolve_withdrawal(:'cad_w', 'completed');
select public.test_assert(
    (public.vault_summary()->>'pending_withdrawal_cents')::bigint = 0
    and (public.vault_summary()->>'available_cents')::bigint
        = 10000 - public.vault_convert_cents(2000, 'CAD', 'EUR'),
    'the CAD payout must leave the EUR vault'
);

select public.test_assert(
    not exists (select 1 from public.vault_reconcile_accounts()),
    'account ledger must reconcile after non-USD FX transfers'
);
select public.test_assert(
    not exists (select 1 from public.vault_reconcile_transactions()),
    'transaction ledger must reconcile after non-USD FX transfers'
);
