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

-- ---------------------------------------------------------------------------
-- Honest table: host $40, guest $50, ante $1. Known deck so Ana (host) has
-- Ah Kh and wins a flush — the same hand as HandRoundTests.
-- ---------------------------------------------------------------------------

select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select public.vault_open('USD');
select id as host_dep from public.vault_create_deposit_intent(10000, 'poker-host-dep') \gset
select status from public.vault_sandbox_confirm_deposit(:'host_dep');

insert into public.open_tables (
    id, invite_code, host_user_id, host_display_name, host_player_key, ante_amount, seats
) values (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'POKER1',
    '11111111-1111-1111-1111-111111111111',
    'Host',
    '11111111-1111-1111-1111-111111111111',
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

\echo '=== P13. recover committed chips by leaving ==='
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select public.poker_start_hand_internal('POKER1', '["2c","Ah","7d","Kh","3h","9h","Jh","4s","5d"]'::jsonb)->>'actingSeat' as next_acting;

-- Left of the new dealer acts first. After hand 1 the button moves to seat 2,
-- so the host (seat 1) is first to act. Have them post the ante, then leave.
select public.poker_act('POKER1', 'call', null, 'leave-host-call');
select public.vault_summary()->>'in_play_cents' as host_in_play_before_leave;
select public.vault_leave_table('POKER1', 'host-leave-midhand') as host_leave \gset
select :'host_leave'::jsonb->>'returned_cents' as returned_cents,
       :'host_leave'::jsonb->>'bought_in_cents' as bought_in_cents;

select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select * from public.vault_table_chips('POKER1');
select public.poker_hand_view('POKER1')->>'isComplete' as hand_complete;
select public.poker_hand_view('POKER1')->>'resultSummary' as result_summary;
select public.vault_summary()->>'in_play_cents' as guest_in_play_after_foldout;

\echo '=== P14. hole cards stay hidden from a direct select as authenticated ==='
set role authenticated;
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select count(*) as visible_hand_rows from public.poker_hands;
select count(*) as visible_hole_rows from public.poker_hand_seats;
reset role;

\echo '=== P15. books still reconcile ==='
select * from public.vault_reconcile_accounts();
select * from public.vault_reconcile_transactions();
