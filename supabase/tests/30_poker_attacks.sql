\set ON_ERROR_STOP on
\pset pager off

-- Poker-engine attacks. Every block must fail (or return nothing) unless the
-- comment says it is the honest path. Uses its own table so it does not depend
-- on leftover state from the vault scripts, other than the same users.

insert into auth.users (id, email) values
    ('11111111-1111-1111-1111-111111111111', 'host@example.com'),
    ('22222222-2222-2222-2222-222222222222', 'guest@example.com'),
    ('33333333-3333-3333-3333-333333333333', 'attacker@example.com')
on conflict (id) do nothing;

-- 10_vault_flow.sql turns self-exclusion on for the guest. This script shares
-- the users, not that restriction.
update public.vault_compliance_profiles
set self_excluded_until = null
where user_id in (
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333'
);

-- ---------------------------------------------------------------------------
-- Honest table: host $40, guest $50, ante $1. Known deck so Ana (host) has
-- Ah Kh and wins a flush — the same hand as HandRoundTests.
-- ---------------------------------------------------------------------------

select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select public.vault_open('USD');
select id as host_dep from public.vault_create_deposit_intent(10000, 'poker-host-dep') \gset
select status from public.vault_sandbox_confirm_deposit(:'host_dep');

insert into public.open_tables (
    id, invite_code, host_user_id, host_display_name, host_player_key,
    session_currency_code, ante_amount, seats
) values (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'POKER1',
    '11111111-1111-1111-1111-111111111111',
    'Host',
    '11111111-1111-1111-1111-111111111111',
    'USD',
    '1',
    '[
        {"id":"10000000-0000-0000-0000-000000000001","seatNumber":1,"playerName":"Host","playerKey":"11111111-1111-1111-1111-111111111111","amount":"40","isHost":true},
        {"id":"10000000-0000-0000-0000-000000000002","seatNumber":2,"playerName":"Guest","playerKey":"22222222-2222-2222-2222-222222222222","amount":"50","isHost":false}
    ]'::jsonb
) on conflict (invite_code) do nothing;

select public.vault_register_table('POKER1', 2000, 8000);
select public.vault_table_buy_in('POKER1', 4000, 'vault', 'poker-host-buy', 'Host');

select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select public.vault_open('USD');
select id as guest_dep from public.vault_create_deposit_intent(10000, 'poker-guest-dep') \gset
select status from public.vault_sandbox_confirm_deposit(:'guest_dep');
select public.vault_table_buy_in('POKER1', 5000, 'vault', 'poker-guest-buy', 'Guest');

select set_config('test.uid', '33333333-3333-3333-3333-333333333333', false);
select public.vault_open('USD');
select id as att_dep from public.vault_create_deposit_intent(10000, 'poker-att-dep') \gset
select status from public.vault_sandbox_confirm_deposit(:'att_dep');

\echo '=== P0. evaluator: ace-high flush beats jack high ==='
select public.poker_best_hand('["Ah","Kh","3h","9h","Jh","4s","5d"]'::jsonb)->>'summary' as host_hand;
select public.poker_best_hand('["2c","7d","3h","9h","Jh","4s","5d"]'::jsonb)->>'summary' as guest_hand;

\echo '=== P1. server deals; clients cannot pass a deck ==='
select count(*) as client_start_with_deck
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'poker_start_hand'
  and pg_get_function_identity_arguments(p.oid) like '%jsonb%';
select public.test_assert(
    (
        select count(*)
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname = 'poker_start_hand'
          and pg_get_function_identity_arguments(p.oid) like '%jsonb%'
    ) = 0,
    'clients must not be able to start a hand with a deck'
);

select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select public.poker_start_hand_internal('POKER1', '["2c","Ah","7d","Kh","3h","9h","Jh","4s","5d"]'::jsonb)
    as host_view \gset

\echo '--- host sees only their hole cards ---'
select jsonb_path_query_first(:'host_view'::jsonb, '$.seats[*] ? (@.playerKey == "11111111-1111-1111-1111-111111111111").cards') as host_cards;
select jsonb_path_query_first(:'host_view'::jsonb, '$.seats[*] ? (@.playerKey == "22222222-2222-2222-2222-222222222222").cards') as guest_cards_from_host;
select :'host_view'::jsonb->>'actingSeat' as acting_seat;
select :'host_view'::jsonb->'deck' as public_deck;

\echo '=== P2. guest view hides the host hole cards ==='
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select public.poker_hand_view('POKER1') as guest_view \gset
select jsonb_path_query_first(:'guest_view'::jsonb, '$.seats[*] ? (@.playerKey == "22222222-2222-2222-2222-222222222222").cards') as guest_cards;
select jsonb_path_query_first(:'guest_view'::jsonb, '$.seats[*] ? (@.playerKey == "11111111-1111-1111-1111-111111111111").cards') as host_cards_from_guest;

\echo '=== P3. an outsider cannot read the hand ==='
select set_config('test.uid', '33333333-3333-3333-3333-333333333333', false);
do $$
begin
    perform public.poker_hand_view('POKER1');
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '=== P4. declare yourself the winner / submit a fabricated result ==='
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
do $$
begin
    perform public.vault_record_hand('POKER1', 'forged-win', '[
        {"player_key": "11111111-1111-1111-1111-111111111111", "delta_cents": -4000},
        {"player_key": "22222222-2222-2222-2222-222222222222", "delta_cents": 4000}
    ]'::jsonb);
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
do $$
begin
    perform public.vault_record_hand('POKER1', 'host-forged', '[
        {"player_key": "11111111-1111-1111-1111-111111111111", "delta_cents": 4000},
        {"player_key": "22222222-2222-2222-2222-222222222222", "delta_cents": -4000}
    ]'::jsonb);
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '=== P5. submit fake cards / change the board / change the pot ==='
do $$
begin
    update public.open_tables
    set hand = jsonb_build_object(
        'isComplete', true,
        'isRevealed', true,
        'board', jsonb_build_array('As','Ks','Qs','Js','Ts'),
        'winnerSeats', jsonb_build_array(2),
        'seats', jsonb_build_array(
            jsonb_build_object(
                'playerKey', '22222222-2222-2222-2222-222222222222',
                'cards', jsonb_build_array('As','Ks'),
                'awarded', '999',
                'committed', '0'
            )
        )
    )
    where invite_code = 'POKER1';
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

select has_table_privilege('authenticated', 'public.poker_hands', 'UPDATE') as can_update_hands,
       has_table_privilege('authenticated', 'public.poker_hands', 'SELECT') as can_select_hands,
       has_table_privilege('authenticated', 'public.poker_hand_seats', 'SELECT') as can_select_seats,
       has_table_privilege('authenticated', 'public.poker_hand_seats', 'UPDATE') as can_update_seats;
select public.test_assert(
    not has_table_privilege('authenticated', 'public.poker_hands', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.poker_hands', 'SELECT')
    and not has_table_privilege('authenticated', 'public.poker_hand_seats', 'SELECT')
    and not has_table_privilege('authenticated', 'public.poker_hand_seats', 'UPDATE'),
    'authenticated must not read or write poker engine tables'
);

\echo '=== P6. act out of turn ==='
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
do $$
begin
    perform public.poker_act('POKER1', 'fold', null, 'host-out-of-turn');
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '=== P7. bet more than you own ==='
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
do $$
begin
    perform public.poker_act('POKER1', 'bet', 999999, 'guest-overbet');
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '=== P8. change another player''s stack via seats ==='
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
do $$
begin
    update public.open_tables
    set seats = '[
        {"playerKey":"11111111-1111-1111-1111-111111111111","seatNumber":1,"playerName":"Host","amount":"1","isHost":true},
        {"playerKey":"22222222-2222-2222-2222-222222222222","seatNumber":2,"playerName":"Guest","amount":"999","isHost":false}
    ]'::jsonb
    where invite_code = 'POKER1';
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '=== P9. outsider cannot act ==='
select set_config('test.uid', '33333333-3333-3333-3333-333333333333', false);
do $$
begin
    perform public.poker_act('POKER1', 'fold', null, 'outsider-act');
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '=== P10. replay a betting action ==='
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select public.poker_act('POKER1', 'call', null, 'guest-call-1') as after_call \gset
select public.poker_act('POKER1', 'call', null, 'guest-call-1') as after_replay \gset
select :'after_call'::jsonb->>'revision' as first_revision,
       :'after_replay'::jsonb->>'revision' as replay_revision;
select (
    select count(*) from public.poker_hand_actions
    where action_id = 'guest-call-1'
) as action_rows;
select public.test_assert(
    (select count(*) from public.poker_hand_actions where action_id = 'guest-call-1') = 1,
    'replayed action must not insert a second row'
);

\echo '--- a second different action from the same player is out of turn ---'
do $$
begin
    perform public.poker_act('POKER1', 'bet', 400, 'guest-act-again');
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '=== P11. honest showdown — the server names the winner ==='
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select public.poker_act('POKER1', 'call', null, 'sd-host-call');
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select public.poker_act('POKER1', 'check', null, 'sd-g-flop');
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select public.poker_act('POKER1', 'check', null, 'sd-h-flop');
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select public.poker_act('POKER1', 'check', null, 'sd-g-turn');
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select public.poker_act('POKER1', 'check', null, 'sd-h-turn');
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select public.poker_act('POKER1', 'check', null, 'sd-g-river');
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select public.poker_act('POKER1', 'check', null, 'sd-h-river') as showdown \gset

select :'showdown'::jsonb->>'isComplete' as complete,
       :'showdown'::jsonb->>'isRevealed' as revealed,
       :'showdown'::jsonb->>'resultSummary' as result,
       :'showdown'::jsonb->>'winnerSeats' as winners,
       :'showdown'::jsonb->'board' as board;
select public.test_assert(
    (:'showdown'::jsonb->>'isComplete')::boolean
    and (:'showdown'::jsonb->>'isRevealed')::boolean
    and (:'showdown'::jsonb->>'winnerSeats') is not null,
    'server showdown must complete, reveal, and name a winner'
);

select * from public.vault_table_chips('POKER1') order by player_key;

\echo '=== P12. settle the same hand twice ==='
do $$
declare
    hid uuid;
begin
    select id into hid from public.poker_hands
    where invite_code = 'POKER1' order by hand_number desc limit 1;
    perform public.poker_apply_vault_settlement(hid);
    perform public.poker_apply_vault_settlement(hid);
end;
$$;
select count(*) as hand_ledger_rows
from public.vault_ledger_transactions
where kind = 'table_hand' and table_invite_code = 'POKER1';
select public.test_assert(
    (
        select count(*) from public.vault_ledger_transactions
        where kind = 'table_hand' and table_invite_code = 'POKER1'
    ) = 1,
    'the same hand must settle once'
);

\echo '=== P13. recover committed chips by leaving ==='
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select public.poker_start_hand_internal('POKER1', '["2c","Ah","7d","Kh","3h","9h","Jh","4s","5d"]'::jsonb)->>'actingSeat' as next_acting;

-- Left of the new dealer acts first. After hand 1 the button moves to seat 2,
-- so the host (seat 1) is first to act. Have them post the ante, then leave.
select public.poker_act('POKER1', 'call', null, 'leave-host-call');
select in_play_cents as host_poker1_before_leave
from public.vault_table_stakes
where invite_code = 'POKER1'
  and user_id = '11111111-1111-1111-1111-111111111111' \gset
select public.vault_leave_table('POKER1', 'host-leave-midhand') as host_leave \gset
select :'host_leave'::jsonb->>'returned_cents' as returned_cents,
       :'host_leave'::jsonb->>'bought_in_cents' as bought_in_cents;

-- The host had posted the ante. Walking out must not give that 100 cents back.
select (
    (:'host_leave'::jsonb->>'returned_cents')::bigint
    = :'host_poker1_before_leave'::bigint - 100
) as host_left_without_committed_ante;
select public.test_assert(
    (:'host_leave'::jsonb->>'returned_cents')::bigint
    = :'host_poker1_before_leave'::bigint - 100,
    'leaving mid-hand must withhold the committed ante'
);

select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select * from public.vault_table_chips('POKER1');
select public.poker_hand_view('POKER1')->>'isComplete' as hand_complete;
select public.poker_hand_view('POKER1')->>'resultSummary' as result_summary;
select public.vault_summary()->>'in_play_cents' as guest_in_play_after_foldout;

\echo '=== P14. hole cards stay hidden from a direct select as authenticated ==='
select has_table_privilege('authenticated', 'public.poker_hands', 'SELECT') as can_select_hands,
       has_table_privilege('authenticated', 'public.poker_hand_seats', 'SELECT') as can_select_seats,
       has_table_privilege('authenticated', 'public.poker_hand_actions', 'SELECT') as can_select_actions;
select public.test_assert(
    not has_table_privilege('authenticated', 'public.poker_hands', 'SELECT')
    and not has_table_privilege('authenticated', 'public.poker_hand_seats', 'SELECT')
    and not has_table_privilege('authenticated', 'public.poker_hand_actions', 'SELECT'),
    'authenticated must not select hole cards or actions'
);

\echo '=== P15. books still reconcile ==='
select * from public.vault_reconcile_accounts();
select * from public.vault_reconcile_transactions();
select public.test_assert(
    not exists (select 1 from public.vault_reconcile_accounts()),
    'account ledger must reconcile after POKER1'
);
select public.test_assert(
    not exists (select 1 from public.vault_reconcile_transactions()),
    'transaction ledger must reconcile after POKER1'
);

-- ---------------------------------------------------------------------------
-- Fresh table for the remaining attacks, so they do not depend on POKER1.
-- Host £40 / guest £50 / ante £1, all integer pence of GBP.
-- ---------------------------------------------------------------------------

select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
insert into public.open_tables (
    id, invite_code, host_user_id, host_display_name, host_player_key,
    session_currency_code, ante_amount, seats
) values (
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    'POKER2',
    '11111111-1111-1111-1111-111111111111',
    'Host',
    '11111111-1111-1111-1111-111111111111',
    'GBP',
    '1',
    '[
        {"id":"20000000-0000-0000-0000-000000000001","seatNumber":1,"playerName":"Host","playerKey":"11111111-1111-1111-1111-111111111111","amount":"40","isHost":true},
        {"id":"20000000-0000-0000-0000-000000000002","seatNumber":2,"playerName":"Guest","playerKey":"22222222-2222-2222-2222-222222222222","amount":"50","isHost":false}
    ]'::jsonb
);

-- Client asks to register the table as USD. The server must keep GBP.
select currency_code as registered_as
from public.vault_register_table('POKER2', 2000, 8000, 'USD');
select public.test_assert(
    (select currency_code from public.vault_tables where invite_code = 'POKER2') = 'GBP',
    'registering as USD must not change a GBP table'
);

select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select public.vault_open('GBP');
select id as host_gbp_dep from public.vault_create_deposit_intent(
    10000, 'poker2-host-dep', 'vault_deposit', null, 'mock_apple_pay', 'GBP'
) \gset
select status from public.vault_sandbox_confirm_deposit(:'host_gbp_dep');
select public.vault_table_buy_in('POKER2', 4000, 'vault', 'poker2-host-buy', 'Host');

select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select public.vault_open('GBP');
select id as guest_gbp_dep from public.vault_create_deposit_intent(
    10000, 'poker2-guest-dep', 'vault_deposit', null, 'mock_apple_pay', 'GBP'
) \gset
select status from public.vault_sandbox_confirm_deposit(:'guest_gbp_dep');
select public.vault_table_buy_in('POKER2', 5000, 'vault', 'poker2-guest-buy', 'Guest');

\echo '=== P16. a display-currency lie cannot change the table''s settlement unit ==='
select currency_code as vault_table_currency
from public.vault_tables where invite_code = 'POKER2';

select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
update public.open_tables
set session_currency_code = 'EUR'
where invite_code = 'POKER2';
select session_currency_code as currency_after_host_flip
from public.open_tables where invite_code = 'POKER2';
select currency_code as vault_currency_after_flip
from public.vault_tables where invite_code = 'POKER2';
select public.test_assert(
    (select session_currency_code from public.open_tables where invite_code = 'POKER2') = 'GBP'
    and (select currency_code from public.vault_tables where invite_code = 'POKER2') = 'GBP',
    'host must not flip the table settlement currency'
);

\echo '=== P17. fake completion / clearing the shared hand cannot enable a cash-out ==='
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select public.poker_start_hand_internal(
    'POKER2',
    '["2c","Ah","7d","Kh","3h","9h","Jh","4s","5d"]'::jsonb
)->>'actingSeat' as poker2_acting;

-- Guest is first to act (host is the dealer) and posts the £1 ante.
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select public.poker_act('POKER2', 'call', null, 'p2-guest-ante');

select in_play_cents as guest_in_play_before_forge
from public.vault_table_stakes
where invite_code = 'POKER2'
  and user_id = '22222222-2222-2222-2222-222222222222' \gset

do $$
begin
    update public.open_tables
    set hand = jsonb_build_object('isComplete', true, 'winnerSeats', jsonb_build_array(2))
    where invite_code = 'POKER2';
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

do $$
begin
    update public.open_tables
    set hand = null
    where invite_code = 'POKER2';
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

-- Mixed write from the host: keep a legal setting touch and wipe the hand
-- at the same time. The hand must stay, and leaving must still withhold.
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
update public.open_tables
set host_display_name = 'Table Host',
    hand = null
where invite_code = 'POKER2';

select (hand ? 'isComplete') as server_hand_survived_mixed_clear
from public.open_tables where invite_code = 'POKER2';
select public.test_assert(
    (select hand ? 'isComplete' from public.open_tables where invite_code = 'POKER2'),
    'a mixed host write must not clear the server hand'
);

select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select public.vault_leave_table('POKER2', 'guest-forge-leave') as guest_forge_leave \gset
select :'guest_forge_leave'::jsonb->>'returned_cents' as forged_leave_returned;
select (
    (:'guest_forge_leave'::jsonb->>'returned_cents')::bigint
    = :'guest_in_play_before_forge'::bigint - 100
) as forged_leave_withheld_the_ante;
select public.test_assert(
    (:'guest_forge_leave'::jsonb->>'returned_cents')::bigint
    = :'guest_in_play_before_forge'::bigint - 100,
    'forged completion must not return committed chips'
);

select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select in_play_cents as host_in_play_after_guest_foldout
from public.vault_table_stakes
where invite_code = 'POKER2'
  and user_id = '11111111-1111-1111-1111-111111111111';

\echo '=== P18. disconnect timeout folds; committed chips stay in the pot ==='
-- Guest already left POKER2. Use a fresh USD table so both players can act.

insert into public.open_tables (
    id, invite_code, host_user_id, host_display_name, host_player_key,
    session_currency_code, ante_amount, seats
) values (
    'dddddddd-dddd-dddd-dddd-dddddddddddd',
    'POKER3',
    '11111111-1111-1111-1111-111111111111',
    'Host',
    '11111111-1111-1111-1111-111111111111',
    'USD',
    '1',
    '[
        {"id":"30000000-0000-0000-0000-000000000001","seatNumber":1,"playerName":"Host","playerKey":"11111111-1111-1111-1111-111111111111","amount":"40","isHost":true},
        {"id":"30000000-0000-0000-0000-000000000002","seatNumber":2,"playerName":"Guest","playerKey":"22222222-2222-2222-2222-222222222222","amount":"50","isHost":false}
    ]'::jsonb
);

select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select public.vault_open('USD');
select public.vault_register_table('POKER3', 2000, 8000, 'USD');
select public.vault_table_buy_in('POKER3', 4000, 'vault', 'poker3-host-buy', 'Host');
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select public.vault_open('USD');
select public.vault_table_buy_in('POKER3', 5000, 'vault', 'poker3-guest-buy', 'Guest');

select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select public.poker_start_hand_internal(
    'POKER3',
    '["2c","Ah","7d","Kh","3h","9h","Jh","4s","5d"]'::jsonb
);
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select public.poker_act('POKER3', 'call', null, 'p3-guest-ante');
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select public.poker_act('POKER3', 'raise', 400, 'p3-host-raise');

update public.poker_hands
set action_deadline = clock_timestamp() - interval '1 second'
where invite_code = 'POKER3' and not is_complete;

select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select public.poker_sweep_timeouts('POKER3') as timeout_view \gset
select :'timeout_view'::jsonb->>'isComplete' as timeout_complete,
       :'timeout_view'::jsonb->>'resultSummary' as timeout_result,
       :'timeout_view'::jsonb->>'winnerSeats' as timeout_winners;

select * from public.vault_table_chips('POKER3') order by player_key;

-- Guest called £1 / $1 and then timed out. Host raised to $4 and won the pot.
-- Guest must be down 100 cents; host up 100. The 100 committed chips stayed.
select (
    (select in_play_cents from public.vault_table_stakes
     where invite_code = 'POKER3'
       and user_id = '22222222-2222-2222-2222-222222222222')
    = 4900
) as guest_lost_committed_on_timeout,
(
    (select in_play_cents from public.vault_table_stakes
     where invite_code = 'POKER3'
       and user_id = '11111111-1111-1111-1111-111111111111')
    = 4100
) as host_was_paid_the_pot;
select public.test_assert(
    (select in_play_cents from public.vault_table_stakes
     where invite_code = 'POKER3'
       and user_id = '22222222-2222-2222-2222-222222222222') = 4900
    and (select in_play_cents from public.vault_table_stakes
         where invite_code = 'POKER3'
           and user_id = '11111111-1111-1111-1111-111111111111') = 4100,
    'timeout fold must keep committed chips in the pot'
);

\echo '=== P19. unauthorized users cannot read live table state ==='
set role authenticated;
select set_config('test.uid', '33333333-3333-3333-3333-333333333333', false);
select count(*) as outsider_live_rows
from public.open_tables
where invite_code in ('POKER1', 'POKER2', 'POKER3');
select public.test_assert(
    (
        select count(*) from public.open_tables
        where invite_code in ('POKER1', 'POKER2', 'POKER3')
    ) = 0,
    'an outsider must not read live table rows'
);
select public.open_table_preview('POKER3') as preview \gset
reset role;

select :'preview'::jsonb ? 'hand' as preview_has_hand,
       :'preview'::jsonb ? 'board' as preview_has_board,
       jsonb_typeof(:'preview'::jsonb->'seats') as preview_seats,
       :'preview'::jsonb->'seats'->0 ? 'cards' as preview_seat_has_cards,
       :'preview'::jsonb->'seats'->0->>'amount' as preview_seat_amount;

select set_config('test.uid', '33333333-3333-3333-3333-333333333333', false);
do $$
begin
    perform public.poker_hand_view('POKER3');
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

do $$
begin
    perform public.poker_sweep_timeouts('POKER3');
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '=== P20. clients cannot write stacks, board, pot, turn or a winner ==='
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
update public.open_tables
set seats = '[
    {"playerKey":"11111111-1111-1111-1111-111111111111","seatNumber":1,"playerName":"Host","amount":"999","isHost":true},
    {"playerKey":"22222222-2222-2222-2222-222222222222","seatNumber":2,"playerName":"Guest","amount":"1","isHost":false}
]'::jsonb
where invite_code = 'POKER3';

select bool_or(seat->>'playerKey' = '11111111-1111-1111-1111-111111111111'
               and seat->>'amount' = '41') as host_stack_from_vault,
       bool_or(seat->>'playerKey' = '22222222-2222-2222-2222-222222222222'
               and seat->>'amount' = '49') as guest_stack_from_vault
from public.open_tables t,
     jsonb_array_elements(t.seats) seat
where t.invite_code = 'POKER3';
select public.test_assert(
    (
        select bool_or(seat->>'playerKey' = '11111111-1111-1111-1111-111111111111'
                       and seat->>'amount' = '41')
        from public.open_tables t,
             jsonb_array_elements(t.seats) seat
        where t.invite_code = 'POKER3'
    )
    and (
        select bool_or(seat->>'playerKey' = '22222222-2222-2222-2222-222222222222'
                       and seat->>'amount' = '49')
        from public.open_tables t,
             jsonb_array_elements(t.seats) seat
        where t.invite_code = 'POKER3'
    ),
    'rewritten stacks must be overwritten from the Vault'
);

do $$
begin
    update public.open_tables
    set hand = jsonb_build_object(
        'board', jsonb_build_array('As','Ks','Qs','Js','Ts'),
        'actingSeat', 2,
        'isComplete', true,
        'winnerSeats', jsonb_build_array(2)
    )
    where invite_code = 'POKER3';
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

select count(*) as leftover_client_hand_writers
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('update_open_table_hand', 'publish_open_table_hand')
  and pg_get_function_identity_arguments(p.oid) like '%jsonb%';
select public.test_assert(
    (
        select count(*)
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname in ('update_open_table_hand', 'publish_open_table_hand')
          and pg_get_function_identity_arguments(p.oid) like '%jsonb%'
    ) = 0,
    'there must be no client RPC that writes the hand'
);

\echo '=== P21. GBP settlement is integer pence, not a converted USD figure ==='
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select in_play_cents as host_gbp_chips
from public.vault_table_stakes
where invite_code = 'POKER2'
  and user_id = '11111111-1111-1111-1111-111111111111';
select (
    (select in_play_cents from public.vault_table_stakes
     where invite_code = 'POKER2'
       and user_id = '11111111-1111-1111-1111-111111111111')
    = 4100
) as host_won_100_gbp_pence,
(
    (select currency_code from public.vault_tables where invite_code = 'POKER2')
    = 'GBP'
) as settlement_currency_is_gbp;
select public.test_assert(
    (select in_play_cents from public.vault_table_stakes
     where invite_code = 'POKER2'
       and user_id = '11111111-1111-1111-1111-111111111111') = 4100
    and (select currency_code from public.vault_tables where invite_code = 'POKER2') = 'GBP',
    'GBP settlement must stay integer pence of GBP'
);

\echo '=== P22. books still reconcile after the extra attacks ==='
select * from public.vault_reconcile_accounts();
select * from public.vault_reconcile_transactions();
select public.test_assert(
    not exists (select 1 from public.vault_reconcile_accounts()),
    'account ledger must reconcile after extra attacks'
);
select public.test_assert(
    not exists (select 1 from public.vault_reconcile_transactions()),
    'transaction ledger must reconcile after extra attacks'
);
