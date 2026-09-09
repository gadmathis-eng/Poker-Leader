\set ON_ERROR_STOP on
\pset pager off

-- Post-hardening attacks. Every block must fail (or return nothing) unless the
-- comment says it is the honest path. Run after 10_vault_flow.sql so the host
-- still has ABC123 published, registered, and seated.

insert into auth.users (id, email) values
    ('33333333-3333-3333-3333-333333333333', 'attacker@example.com')
on conflict (id) do nothing;

\echo '=== A1. a guest cannot register someone else''s table ==='
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
do $$
begin
    perform public.vault_register_table('ABC123', 1, 999999);
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '=== A2. an unpublished code cannot be registered ==='
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
do $$
begin
    perform public.vault_register_table('ZZZ999', 2000, 8000);
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '=== A3. buy-in identity is the JWT — a spoofed player_key argument is gone ==='
select set_config('test.uid', '33333333-3333-3333-3333-333333333333', false);
select public.vault_open('USD');
select id as att_intent from public.vault_create_deposit_intent(10000, 'dep-att-1') \gset
select status from public.vault_sandbox_confirm_deposit(:'att_intent');
do $$
begin
    -- The old six-text signature accepted p_player_key. It must not exist.
    perform public.vault_table_buy_in(
        'ABC123', 4000, 'vault', 'buyin-spoof',
        '11111111-1111-1111-1111-111111111111', 'Stolen'
    );
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '=== A4. the two-argument sandbox confirm (client-chosen outcome) is gone ==='
select count(*) as leftover_confirm_overloads
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'vault_sandbox_confirm_deposit'
  and pg_get_function_identity_arguments(p.oid) = 'p_intent_id uuid, p_outcome text';
select public.test_assert(
    (
        select count(*)
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname = 'vault_sandbox_confirm_deposit'
          and pg_get_function_identity_arguments(p.oid) = 'p_intent_id uuid, p_outcome text'
    ) = 0,
    'client-chosen deposit outcome must not exist'
);

\echo '=== A5. cancel never credits money ==='
select set_config('test.uid', '33333333-3333-3333-3333-333333333333', false);
select id as att_cancel from public.vault_create_deposit_intent(2500, 'dep-att-cancel') \gset
select status from public.vault_cancel_deposit_intent(:'att_cancel');
select public.vault_summary()->>'available_cents' as available_after_cancel;
select public.test_assert(
    (public.vault_summary()->>'available_cents')::bigint = 10000,
    'cancel must not credit the pending deposit'
);

\echo '=== A6. a guest cannot rewrite another player''s seat ==='
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
do $$
begin
    update public.open_tables
    set seats = '[
        {"playerKey":"11111111-1111-1111-1111-111111111111","seatNumber":1,"playerName":"Stolen","amount":"999"},
        {"playerKey":"22222222-2222-2222-2222-222222222222","seatNumber":2,"playerName":"Guest","amount":"1"}
    ]'::jsonb
    where invite_code = 'ABC123';
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '=== A7. merge_open_table_seat ignores a forged playerKey ==='
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select public.merge_open_table_seat('ABC123', jsonb_build_object(
    'playerKey', '11111111-1111-1111-1111-111111111111',
    'seatNumber', 2,
    'playerName', 'Not The Host',
    'amount', '1',
    'isHost', true
));
select bool_or(seat->>'playerKey' = '22222222-2222-2222-2222-222222222222') as caller_key_used,
       bool_or(seat->>'playerKey' = '11111111-1111-1111-1111-111111111111'
               and coalesce(seat->>'playerName', '') = 'Not The Host') as forged_host_rejected
from public.open_tables t,
     jsonb_array_elements(t.seats) seat
where t.invite_code = 'ABC123';
select public.test_assert(
    (
        select bool_or(seat->>'playerKey' = '22222222-2222-2222-2222-222222222222')
        from public.open_tables t,
             jsonb_array_elements(t.seats) seat
        where t.invite_code = 'ABC123'
    )
    and not coalesce((
        select bool_or(seat->>'playerKey' = '11111111-1111-1111-1111-111111111111'
                       and coalesce(seat->>'playerName', '') = 'Not The Host')
        from public.open_tables t,
             jsonb_array_elements(t.seats) seat
        where t.invite_code = 'ABC123'
    ), false),
    'merge must use the JWT player and ignore a forged host key'
);

\echo '=== A8. a guest cannot change the ante or start the table ==='
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
do $$
begin
    update public.open_tables
    set ante_amount = '50', is_started = true
    where invite_code = 'ABC123';
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '=== A9. identity columns are immutable, even for the host ==='
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
do $$
begin
    update public.open_tables
    set host_user_id = '33333333-3333-3333-3333-333333333333'
    where invite_code = 'ABC123';
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '=== A10. a client cannot write the hand, even as the host ==='
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
do $$
begin
    update public.open_tables
    set hand = jsonb_build_object(
        'isComplete', true,
        'winnerSeats', jsonb_build_array(1),
        'seats', jsonb_build_array(
            jsonb_build_object('playerKey', '11111111-1111-1111-1111-111111111111', 'awarded', '999')
        )
    )
    where invite_code = 'ABC123';
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '=== A11. over-withdrawal is refused ==='
select set_config('test.uid', '33333333-3333-3333-3333-333333333333', false);
do $$
begin
    perform public.vault_request_withdrawal(99999999, 'cashout-huge-att');
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;

\echo '=== A12. privacy: another player''s vault rows are invisible ==='
set role authenticated;
select set_config('test.uid', '33333333-3333-3333-3333-333333333333', false);
select count(*) as foreign_accounts
from public.vault_accounts
where owner_user_id = '11111111-1111-1111-1111-111111111111';
select count(*) as foreign_statement
from public.vault_statement_entries
where user_id = '11111111-1111-1111-1111-111111111111';
select public.test_assert(
    (select count(*) from public.vault_accounts
     where owner_user_id = '11111111-1111-1111-1111-111111111111') = 0
    and (select count(*) from public.vault_statement_entries
         where user_id = '11111111-1111-1111-1111-111111111111') = 0,
    'another player must not see the host vault'
);
reset role;

\echo '=== A13. direct ledger writes are impossible ==='
set role authenticated;
select set_config('test.uid', '33333333-3333-3333-3333-333333333333', false);
do $$
begin
    insert into public.vault_ledger_entries (transaction_id, account_id, amount_cents)
    select t.id, a.id, 1
    from public.vault_ledger_transactions t
    join public.vault_accounts a on true
    limit 1;
    raise exception 'expected failure';
exception when others then
    if sqlerrm like 'expected failure%' then raise; end if;
    raise notice 'rejected as expected: %', sqlerrm;
end;
$$;
reset role;

\echo '=== A14. authenticated cannot insert or update vault balances ==='
select has_table_privilege('authenticated', 'public.vault_accounts', 'INSERT') as can_insert_accounts,
       has_table_privilege('authenticated', 'public.vault_accounts', 'UPDATE') as can_update_accounts,
       has_table_privilege('authenticated', 'public.vault_ledger_entries', 'INSERT') as can_insert_entries,
       has_table_privilege('authenticated', 'public.vault_ledger_transactions', 'INSERT') as can_insert_tx;
select public.test_assert(
    not has_table_privilege('authenticated', 'public.vault_accounts', 'INSERT')
    and not has_table_privilege('authenticated', 'public.vault_accounts', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.vault_ledger_entries', 'INSERT')
    and not has_table_privilege('authenticated', 'public.vault_ledger_transactions', 'INSERT'),
    'authenticated must not write vault balances or ledger rows'
);
select count(*) as leftover_confirm_with_outcome
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'vault_sandbox_confirm_deposit'
  and pg_get_function_identity_arguments(p.oid) like '%text%';
select count(*) as leftover_buy_in_with_player_key
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'vault_table_buy_in'
  and pg_get_function_identity_arguments(p.oid) like '%p_player_key%';
select public.test_assert(
    (
        select count(*)
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname = 'vault_sandbox_confirm_deposit'
          and pg_get_function_identity_arguments(p.oid) like '%text%'
    ) = 0
    and (
        select count(*)
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname = 'vault_table_buy_in'
          and pg_get_function_identity_arguments(p.oid) like '%p_player_key%'
    ) = 0,
    'old deposit-outcome and player_key buy-in signatures must be gone'
);

\echo '=== A15. books still reconcile ==='
select * from public.vault_reconcile_accounts();
select * from public.vault_reconcile_transactions();
select public.test_assert(
    not exists (select 1 from public.vault_reconcile_accounts()),
    'account ledger must reconcile after attacks'
);
select public.test_assert(
    not exists (select 1 from public.vault_reconcile_transactions()),
    'transaction ledger must reconcile after attacks'
);
