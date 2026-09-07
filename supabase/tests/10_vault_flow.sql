\set ON_ERROR_STOP on
\pset pager off

insert into auth.users (id, email) values
    ('11111111-1111-1111-1111-111111111111', 'host@example.com'),
    ('22222222-2222-2222-2222-222222222222', 'guest@example.com');

\echo '=== 1. host opens vault, deposits $100 via mock Apple Pay ==='
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select public.vault_open('USD');

select id as intent_id from public.vault_create_deposit_intent(10000, 'dep-1') \gset
\echo '--- summary while the deposit is pending (nothing spendable yet) ---'
select public.vault_summary()->>'available_cents' as available,
       public.vault_summary()->>'pending_deposit_cents' as pending_deposit,
       public.vault_summary()->>'total_cents' as total;

select status, amount_cents from public.vault_sandbox_confirm_deposit(:'intent_id');
\echo '--- replayed confirmation must not add the money twice ---'
select status from public.vault_sandbox_confirm_deposit(:'intent_id');
select public.vault_summary()->>'available_cents' as available,
       public.vault_summary()->>'pending_deposit_cents' as pending_deposit,
       public.vault_summary()->>'total_cents' as total;

\echo '=== 2. guest deposits $50 ==='
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select public.vault_open('USD');
select id as g_intent from public.vault_create_deposit_intent(5000, 'dep-g1') \gset
select status from public.vault_sandbox_confirm_deposit(:'g_intent');

\echo '=== 3. host registers a table, both buy in from the vault ==='
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select invite_code, min_buy_in_cents, max_buy_in_cents from public.vault_register_table('ABC123', 2000, 8000);
select public.vault_table_buy_in('ABC123', 4000, 'vault', 'buyin-host-1', 'host-key', 'Host');
\echo '--- replayed buy-in is ignored ---'
select public.vault_table_buy_in('ABC123', 4000, 'vault', 'buyin-host-1', 'host-key', 'Host');
select public.vault_summary()->>'available_cents' as available,
       public.vault_summary()->>'in_play_cents' as in_play,
       public.vault_summary()->>'total_cents' as total;

select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select public.vault_table_buy_in('ABC123', 3000, 'vault', 'buyin-guest-1', 'guest-key', 'Guest');

\echo '=== 4. guest tops up straight onto the table with Apple Pay ==='
select id as g_table_intent from public.vault_create_deposit_intent(2000, 'buyin-pay-1', 'table_buy_in', 'ABC123') \gset
\echo '--- an unverified payment cannot buy in ---'
do $$
begin
    perform public.vault_table_buy_in('ABC123', 2000, 'apple_pay', 'buyin-guest-2', 'guest-key', 'Guest',
                                      nullif(current_setting('test.intent', true), '')::uuid);
    raise exception 'expected failure';
exception when others then
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;
select set_config('test.intent', :'g_table_intent', false);
select status from public.vault_sandbox_confirm_deposit(:'g_table_intent');
select public.vault_table_buy_in('ABC123', 2000, 'apple_pay', 'buyin-guest-2', 'guest-key', 'Guest', :'g_table_intent');
\echo '--- the same payment cannot be spent twice ---'
do $$
begin
    perform public.vault_table_buy_in('ABC123', 2000, 'apple_pay', 'buyin-guest-3', 'guest-key', 'Guest',
                                      nullif(current_setting('test.intent', true), '')::uuid);
    raise exception 'expected failure';
exception when others then
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '=== 5. chips at the table: visible to seated players, nothing else ==='
select * from public.vault_table_chips('ABC123');
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select * from public.vault_table_chips('ABC123');

\echo '=== 6. host records a hand: guest wins $15 from host ==='
select public.vault_record_hand('ABC123', 'hand-1', '[
    {"player_key": "host-key", "delta_cents": -1500},
    {"player_key": "guest-key", "delta_cents": 1500}
]'::jsonb);
\echo '--- the same hand posted again is ignored ---'
select public.vault_record_hand('ABC123', 'hand-1', '[
    {"player_key": "host-key", "delta_cents": -1500},
    {"player_key": "guest-key", "delta_cents": 1500}
]'::jsonb);
select * from public.vault_table_chips('ABC123');

\echo '--- a hand that is not zero-sum is refused ---'
do $$
begin
    perform public.vault_record_hand('ABC123', 'hand-bogus', '[
        {"player_key": "guest-key", "delta_cents": 999999}
    ]'::jsonb);
    raise exception 'expected failure';
exception when others then
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '--- a player cannot record their own hand ---'
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
do $$
begin
    perform public.vault_record_hand('ABC123', 'hand-2', '[
        {"player_key": "host-key", "delta_cents": -100},
        {"player_key": "guest-key", "delta_cents": 100}
    ]'::jsonb);
    raise exception 'expected failure';
exception when others then
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '=== 7. guest leaves the table ==='
select public.vault_leave_table('ABC123', 'leave-guest-1');
\echo '--- leaving twice returns nothing extra ---'
select public.vault_leave_table('ABC123', 'leave-guest-1');
select public.vault_summary()->>'available_cents' as available,
       public.vault_summary()->>'in_play_cents' as in_play,
       public.vault_summary()->>'total_cents' as total;

\echo '=== 8. guest cashes out $40 ==='
select id as w_id, amount_cents, fee_cents, net_cents, status
from public.vault_request_withdrawal(4000, 'cashout-1') \gset
select public.vault_summary()->>'available_cents' as available,
       public.vault_summary()->>'pending_withdrawal_cents' as pending_withdrawal,
       public.vault_summary()->>'total_cents' as total;
\echo '--- more than is available is refused ---'
do $$
begin
    perform public.vault_request_withdrawal(999999, 'cashout-huge');
    raise exception 'expected failure';
exception when others then
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;
select status, net_cents from public.vault_sandbox_resolve_withdrawal(:'w_id', 'completed');
select public.vault_summary()->>'available_cents' as available,
       public.vault_summary()->>'pending_withdrawal_cents' as pending_withdrawal,
       public.vault_summary()->>'total_cents' as total;

\echo '=== 9. the guest statement ==='
select kind, status, amount_cents, table_invite_code, is_demo
from public.vault_statement(50) order by created_at;

\echo '=== 10. reconciliation: both must be empty ==='
select * from public.vault_reconcile_accounts();
select * from public.vault_reconcile_transactions();

\echo '=== 11. the ledger is immutable ==='
do $$
begin
    update public.vault_ledger_entries set amount_cents = 1;
    raise exception 'expected failure';
exception when others then
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '=== 12. self-exclusion blocks play and deposits ==='
update public.vault_compliance_profiles
set self_excluded_until = now() + interval '30 days'
where user_id = '22222222-2222-2222-2222-222222222222';
do $$
begin
    perform public.vault_create_deposit_intent(1000, 'dep-excluded');
    raise exception 'expected failure';
exception when others then
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;
