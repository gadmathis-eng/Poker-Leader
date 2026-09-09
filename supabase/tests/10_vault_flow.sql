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
select public.test_assert(
    (public.vault_summary()->>'available_cents')::bigint = 10000
    and (public.vault_summary()->>'pending_deposit_cents')::bigint = 0,
    'host deposit must credit $100 once'
);

\echo '=== 2. guest deposits $50 ==='
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select public.vault_open('USD');
select id as g_intent from public.vault_create_deposit_intent(5000, 'dep-g1') \gset
select status from public.vault_sandbox_confirm_deposit(:'g_intent');

\echo '=== 3. host publishes the shared table, then registers the buy-in range ==='
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
insert into public.open_tables (
    id, invite_code, host_user_id, host_display_name, host_player_key
) values (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'ABC123',
    '11111111-1111-1111-1111-111111111111',
    'Host',
    '11111111-1111-1111-1111-111111111111'
);
select invite_code, min_buy_in_cents, max_buy_in_cents from public.vault_register_table('ABC123', 2000, 8000);
select public.vault_table_buy_in('ABC123', 4000, 'vault', 'buyin-host-1', 'Host');
\echo '--- replayed buy-in is ignored ---'
select public.vault_table_buy_in('ABC123', 4000, 'vault', 'buyin-host-1', 'Host');
select public.vault_summary()->>'available_cents' as available,
       public.vault_summary()->>'in_play_cents' as in_play,
       public.vault_summary()->>'total_cents' as total;
select public.test_assert(
    (public.vault_summary()->>'available_cents')::bigint = 6000
    and (public.vault_summary()->>'in_play_cents')::bigint = 4000,
    'host buy-in must move $40 from available to in play'
);

select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select public.vault_table_buy_in('ABC123', 3000, 'vault', 'buyin-guest-1', 'Guest');

\echo '=== 4. guest tops up straight onto the table with Apple Pay ==='
select id as g_table_intent from public.vault_create_deposit_intent(2000, 'buyin-pay-1', 'table_buy_in', 'ABC123') \gset
\echo '--- an unverified payment cannot buy in ---'
do $$
begin
    perform public.vault_table_buy_in('ABC123', 2000, 'apple_pay', 'buyin-guest-2', 'Guest',
                                      nullif(current_setting('test.intent', true), '')::uuid);
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;
select set_config('test.intent', :'g_table_intent', false);
select status from public.vault_sandbox_confirm_deposit(:'g_table_intent');
select public.vault_table_buy_in('ABC123', 2000, 'apple_pay', 'buyin-guest-2', 'Guest', :'g_table_intent');
\echo '--- the same payment cannot be spent twice ---'
do $$
begin
    perform public.vault_table_buy_in('ABC123', 2000, 'apple_pay', 'buyin-guest-3', 'Guest',
                                      nullif(current_setting('test.intent', true), '')::uuid);
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '=== 5. chips at the table: visible to seated players, nothing else ==='
select * from public.vault_table_chips('ABC123');
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select * from public.vault_table_chips('ABC123');

\echo '=== 6. the server plays a hand; clients cannot post a result ==='
update public.open_tables
set ante_amount = '1',
    seats = '[
        {"id":"20000000-0000-0000-0000-000000000001","seatNumber":1,"playerName":"Host","playerKey":"11111111-1111-1111-1111-111111111111","amount":"40","isHost":true},
        {"id":"20000000-0000-0000-0000-000000000002","seatNumber":2,"playerName":"Guest","playerKey":"22222222-2222-2222-2222-222222222222","amount":"50","isHost":false}
    ]'::jsonb
where invite_code = 'ABC123';

-- Guest calls the ante, host folds. Guest is paid $1 from the server result.
select public.poker_start_hand_internal('ABC123', '["2c","Ah","7d","Kh"]'::jsonb);
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select public.poker_act('ABC123', 'call', null, 'flow-guest-call');
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select public.poker_act('ABC123', 'fold', null, 'flow-host-fold');
select * from public.vault_table_chips('ABC123');

\echo '--- a client-supplied hand result is refused, even from the host ---'
do $$
begin
    perform public.vault_record_hand('ABC123', 'hand-bogus', '[
        {"player_key": "22222222-2222-2222-2222-222222222222", "delta_cents": 999999}
    ]'::jsonb);
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
do $$
begin
    perform public.vault_record_hand('ABC123', 'hand-2', '[
        {"player_key": "11111111-1111-1111-1111-111111111111", "delta_cents": -100},
        {"player_key": "22222222-2222-2222-2222-222222222222", "delta_cents": 100}
    ]'::jsonb);
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
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
    if sqlerrm like 'expected failure%' then raise; end if;
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
select public.test_assert(
    not exists (select 1 from public.vault_reconcile_accounts()),
    'account ledger must reconcile'
);
select public.test_assert(
    not exists (select 1 from public.vault_reconcile_transactions()),
    'transaction ledger must reconcile'
);

\echo '=== 11. the ledger is immutable ==='
do $$
begin
    update public.vault_ledger_entries set amount_cents = 1;
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
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
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;
