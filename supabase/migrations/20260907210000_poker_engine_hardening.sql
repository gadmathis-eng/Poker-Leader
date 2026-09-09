-- Pot Master — close the leftover poker-engine holes.
--
-- Paste this whole file into the Supabase SQL Editor and click Run, after
-- 20260907200000_poker_server_engine.sql. It is safe to run more than once.
--
-- WHAT THIS LOCKS DOWN
--   1. Whether a player is in a live hand is read only from poker_hands /
--      poker_hand_seats. open_tables.hand cannot mark a hand complete, clear
--      it, or recover chips already in the pot.
--   2. Clients cannot write the hand, the board, the pot, the turn, stacks,
--      the winner, or completion. Seat chip figures are overwritten from the
--      Vault whenever a stake exists. The host's UPDATE cannot rewrite them.
--   3. A player who disconnects or stops acting is folded by the server after
--      a server-controlled timeout. Committed chips stay in the pot.
--   4. The table's session currency is the unit for buy-ins, bets, stacks,
--      pots and Vault settlement. The client cannot pick a different currency
--      or settle through a display-rate conversion.
--   5. Knowing the six-character code is not enough to read the live table.
--      Joiners get a preview (who is sitting, the ante, the currency). Board,
--      pot, turn and cards require a seat. Hole cards never appear on the
--      shared row.

-- ---------------------------------------------------------------------------
-- Timeout column
-- ---------------------------------------------------------------------------

create or replace function public.poker_draw_card(p_hand_id uuid)
returns text
language plpgsql
volatile
as $$
declare
    remaining jsonb;
    drawn text;
begin
    select h.deck into remaining from public.poker_hands h where h.id = p_hand_id;
    if remaining is null or jsonb_array_length(remaining) = 0 then
        return null;
    end if;
    drawn := remaining->>0;
    update public.poker_hands
    set deck = coalesce(remaining - 0, '[]'::jsonb)
    where id = p_hand_id;
    return drawn;
end;
$$;

revoke all on function public.poker_draw_card(uuid) from public, anon, authenticated;

create or replace function public.poker_rank_five(p_cards jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
    codes text[];
    ranks int[];
    suits text[];
    is_flush boolean;
    straight_high int;
    wheel boolean := false;
    unique_ranks int;
    high int;
    low int;
    groups jsonb := '[]'::jsonb;
    counts int[];
    tiebreakers int[] := '{}';
    category int;
    summary text;
    ordered text[];
    grp_rank int;
    grp_count int;
    leftover text[];
begin
    if jsonb_array_length(coalesce(p_cards, '[]'::jsonb)) <> 5 then
        return null;
    end if;

    select array_agg(code_txt) into codes
    from jsonb_array_elements_text(p_cards) as code_txt;

    ranks := array(
        select public.poker_card_rank(code_txt) from unnest(codes) as code_txt
    );
    suits := array(
        select public.poker_card_suit(code_txt) from unnest(codes) as code_txt
    );

    if ranks @> array[null::int] or array_position(ranks, null) is not null then
        return null;
    end if;

    select array_agg(code_txt order by public.poker_card_rank(code_txt) desc)
    into codes
    from unnest(codes) as code_txt;
    ranks := array(select public.poker_card_rank(code_txt) from unnest(codes) as code_txt);

    is_flush := (select count(distinct suit_txt) = 1 from unnest(suits) as suit_txt);
    unique_ranks := (select count(distinct rank_val) from unnest(ranks) as rank_val);
    high := ranks[1];
    low := ranks[5];

    straight_high := null;
    if unique_ranks = 5 then
        if high - low = 4 then
            straight_high := high;
        elsif ranks[1] = 14 and ranks[2] = 5 and ranks[3] = 4
           and ranks[4] = 3 and ranks[5] = 2 then
            straight_high := 5;
            wheel := true;
        end if;
    end if;

    if wheel then
        ordered := array(
            select code_txt from unnest(codes) as code_txt
            where public.poker_card_rank(code_txt) <> 14
            order by public.poker_card_rank(code_txt) desc
        ) || array(
            select code_txt from unnest(codes) as code_txt
            where public.poker_card_rank(code_txt) = 14
        );
    else
        ordered := codes;
    end if;

    if straight_high is not null then
        category := case when is_flush then 9 else 5 end;
        if category = 9 and straight_high = 14 then
            summary := 'Royal flush';
        elsif category = 9 then
            summary := 'Straight flush, ' || public.poker_rank_name(straight_high) || ' high';
        else
            summary := 'Straight, ' || public.poker_rank_name(straight_high) || ' high';
        end if;
        return jsonb_build_object(
            'category', category,
            'tiebreakers', jsonb_build_array(straight_high),
            'cards', to_jsonb(ordered),
            'summary', summary
        );
    end if;

    if is_flush then
        return jsonb_build_object(
            'category', 6,
            'tiebreakers', to_jsonb(ranks),
            'cards', to_jsonb(codes),
            'summary', 'Flush, ' || public.poker_rank_name(ranks[1]) || ' high'
        );
    end if;

    for grp_rank, grp_count in
        select public.poker_card_rank(code_txt) as rk, count(*)::int
        from unnest(codes) as code_txt
        group by 1
        order by 2 desc, 1 desc
    loop
        leftover := array(
            select code_txt from unnest(codes) as code_txt
            where public.poker_card_rank(code_txt) = grp_rank
        );
        groups := groups || jsonb_build_array(
            jsonb_build_object('rank', grp_rank, 'count', grp_count, 'cards', to_jsonb(leftover))
        );
        tiebreakers := tiebreakers || grp_rank;
        counts := coalesce(counts, '{}') || grp_count;
    end loop;

    ordered := array(
        select jsonb_array_elements_text(g->'cards')
        from jsonb_array_elements(groups) as g
    );

    if counts = array[4, 1] then
        category := 8;
        summary := 'Four of a kind, ' || public.poker_rank_name(tiebreakers[1], true);
    elsif counts = array[3, 2] then
        category := 7;
        summary := 'Full house, ' || public.poker_rank_name(tiebreakers[1], true)
            || ' full of ' || public.poker_rank_name(tiebreakers[2], true);
    elsif counts = array[3, 1, 1] then
        category := 4;
        summary := 'Three of a kind, ' || public.poker_rank_name(tiebreakers[1], true);
    elsif counts = array[2, 2, 1] then
        category := 3;
        summary := 'Two pair, ' || public.poker_rank_name(tiebreakers[1], true)
            || ' and ' || public.poker_rank_name(tiebreakers[2], true);
    elsif counts = array[2, 1, 1, 1] then
        category := 2;
        summary := 'Pair of ' || public.poker_rank_name(tiebreakers[1], true);
    else
        category := 1;
        summary := initcap(public.poker_rank_name(tiebreakers[1])) || ' high';
    end if;

    return jsonb_build_object(
        'category', category,
        'tiebreakers', to_jsonb(tiebreakers),
        'cards', to_jsonb(ordered),
        'summary', summary
    );
end;
$$;

revoke all on function public.poker_rank_five(jsonb) from public, anon, authenticated;

create or replace function public.poker_action_order(p_seats integer[], p_dealer integer)
returns integer[]
language plpgsql
immutable
as $$
declare
    sorted integer[];
    pivot int;
begin
    select array_agg(s order by s) into sorted from unnest(p_seats) as s;
    if sorted is null then
        return '{}';
    end if;
    select min(idx) into pivot
    from generate_subscripts(sorted, 1) as idx
    where sorted[idx] > p_dealer;
    if pivot is null then
        return sorted;
    end if;
    return sorted[pivot:] || sorted[:pivot-1];
end;
$$;

create or replace function public.poker_next_acting_seat(p_hand_id uuid, p_after integer)
returns integer
language plpgsql
stable
as $$
declare
    hand public.poker_hands;
    order_seats integer[];
    start_at int := 1;
    step int;
    seat_no int;
    rec record;
    call_target bigint;
    contenders int;
begin
    select * into hand from public.poker_hands where id = p_hand_id;
    select count(*) into contenders
    from public.poker_hand_seats
    where poker_hand_seats.hand_id = p_hand_id and not is_folded;
    if contenders < 2 then
        return null;
    end if;

    select public.poker_action_order(array_agg(seat_number), hand.dealer_seat)
    into order_seats
    from public.poker_hand_seats
    where poker_hand_seats.hand_id = p_hand_id;

    if order_seats is null or array_length(order_seats, 1) is null then
        return null;
    end if;

    call_target := public.poker_call_target(p_hand_id);
    if p_after is not null then
        select min(idx) into start_at
        from generate_subscripts(order_seats, 1) as idx
        where order_seats[idx] = p_after;
        if start_at is null then
            start_at := 1;
        else
            start_at := start_at + 1;
        end if;
    end if;

    for step in 0 .. coalesce(array_length(order_seats, 1), 0) - 1 loop
        seat_no := order_seats[1 + ((start_at - 1 + step) % array_length(order_seats, 1))];
        select * into rec
        from public.poker_hand_seats
        where poker_hand_seats.hand_id = p_hand_id and seat_number = seat_no;
        if public.poker_needs_action(
            rec.is_folded,
            public.poker_remaining(rec.stack_cents, rec.committed_cents),
            rec.has_acted,
            rec.street_committed_cents,
            call_target
        ) then
            return seat_no;
        end if;
    end loop;
    return null;
end;
$$;

alter table public.poker_hands
    add column if not exists action_deadline timestamptz;

create or replace function public.poker_action_timeout()
returns interval
language sql
stable
as $$
    select coalesce(
        nullif(current_setting('poker.action_timeout', true), '')::interval,
        interval '45 seconds'
    );
$$;

create or replace function public.poker_hands_touch_deadline()
returns trigger
language plpgsql
as $$
begin
    if new.is_complete or new.acting_seat is null then
        new.action_deadline := null;
    elsif tg_op = 'INSERT'
          or new.acting_seat is distinct from old.acting_seat then
        new.action_deadline := clock_timestamp() + public.poker_action_timeout();
    end if;
    return new;
end;
$$;

drop trigger if exists poker_hands_touch_deadline on public.poker_hands;
create trigger poker_hands_touch_deadline
    before insert or update on public.poker_hands
    for each row execute function public.poker_hands_touch_deadline();

-- ---------------------------------------------------------------------------
-- Who may see or advance a table
-- ---------------------------------------------------------------------------

create or replace function public.open_table_is_host(p_invite_code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.open_tables
        where invite_code = upper(trim(p_invite_code))
          and host_user_id = auth.uid()
    );
$$;

create or replace function public.open_table_is_seated(p_invite_code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select public.open_table_holds_seat(
        (select seats from public.open_tables where invite_code = upper(trim(p_invite_code))),
        coalesce(auth.uid()::text, '')
    );
$$;

create or replace function public.open_table_is_authorized(p_invite_code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select public.open_table_is_host(p_invite_code)
        or public.open_table_is_seated(p_invite_code);
$$;

revoke all on function public.open_table_is_host(text) from public, anon;
revoke all on function public.open_table_is_seated(text) from public, anon;
revoke all on function public.open_table_is_authorized(text) from public, anon;
grant execute on function public.open_table_is_host(text) to authenticated, service_role;
grant execute on function public.open_table_is_seated(text) to authenticated, service_role;
grant execute on function public.open_table_is_authorized(text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Seat amounts come from the Vault, not from the phone
-- ---------------------------------------------------------------------------

create or replace function public.open_tables_sanitize_seats(p_seats jsonb, p_invite_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    code text := upper(trim(p_invite_code));
    next_seats jsonb := '[]'::jsonb;
    item jsonb;
    stake public.vault_table_stakes;
    amount text;
begin
    for item in select value from jsonb_array_elements(coalesce(p_seats, '[]'::jsonb))
    loop
        stake := null;
        select * into stake
        from public.vault_table_stakes
        where invite_code = code
          and player_key = item->>'playerKey'
          and status = 'seated';

        if found then
            amount := public.poker_cents_text(stake.in_play_cents);
            item := item || jsonb_build_object('amount', amount);
        end if;
        next_seats := next_seats || jsonb_build_array(item);
    end loop;
    return next_seats;
end;
$$;

-- ---------------------------------------------------------------------------
-- Insert / update guards: the engine writes the hand; phones do not
-- ---------------------------------------------------------------------------

create or replace function public.open_tables_guard_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    caller text := public.open_table_seat_key();
begin
    if current_setting('poker.engine', true) = 'on' then
        return new;
    end if;

    if caller <> '' and new.host_user_id::text <> caller then
        raise exception 'open_tables: only the host can publish this table'
            using errcode = '42501';
    end if;

    new.hand := null;
    new.seats := public.open_tables_sanitize_seats(new.seats, new.invite_code);
    return new;
end;
$$;

drop trigger if exists open_tables_guard_insert on public.open_tables;
create trigger open_tables_guard_insert
    before insert on public.open_tables
    for each row execute function public.open_tables_guard_insert();

create or replace function public.open_tables_guard_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    caller text := public.open_table_seat_key();
    is_host boolean;
    registered boolean;
    hand_only boolean;
begin
    if current_setting('poker.engine', true) = 'on' then
        return new;
    end if;

    -- No auth.uid() means service_role or a migration, not a player.
    if caller = '' then
        return new;
    end if;

    if new.id <> old.id
       or new.invite_code <> old.invite_code
       or new.host_user_id <> old.host_user_id
       or new.created_at <> old.created_at then
        raise exception 'open_tables: that table''s identity cannot be changed'
            using errcode = '42501';
    end if;

    -- The hand, board, pot, turn, winner and completion are the server's.
    -- A write that only touches the hand is refused. A mixed update keeps
    -- the server hand even if the payload carried a stale or forged copy.
    if new.hand is distinct from old.hand then
        hand_only :=
            new.seats is not distinct from old.seats
            and new.ante_amount is not distinct from old.ante_amount
            and new.is_started is not distinct from old.is_started
            and new.session_currency_code is not distinct from old.session_currency_code
            and coalesce(new.host_display_name, '')
                is not distinct from coalesce(old.host_display_name, '')
            and coalesce(new.host_player_key, '')
                is not distinct from coalesce(old.host_player_key, '');
        if hand_only then
            raise exception 'open_tables: the server owns the hand'
                using errcode = '42501';
        end if;
        new.hand := old.hand;
    end if;

    select exists (
        select 1 from public.vault_tables where invite_code = old.invite_code
    ) into registered;

    -- Once the table is registered, its currency is the settlement unit.
    -- A host cannot flip it to make cents mean something else.
    if registered then
        new.session_currency_code := old.session_currency_code;
    end if;

    new.seats := public.open_tables_sanitize_seats(new.seats, old.invite_code);

    is_host := old.host_user_id::text = caller;
    if is_host then
        return new;
    end if;

    if new.session_currency_code is distinct from old.session_currency_code
       or new.ante_amount is distinct from old.ante_amount
       or new.is_started is distinct from old.is_started
       or coalesce(new.host_display_name, '') is distinct from coalesce(old.host_display_name, '')
       or coalesce(new.host_player_key, '') is distinct from coalesce(old.host_player_key, '') then
        raise exception 'open_tables: only the host can change this table''s settings'
            using errcode = '42501';
    end if;

    if public.open_table_other_seats(new.seats, caller)
       <> public.open_table_other_seats(old.seats, caller) then
        raise exception 'open_tables: you can only change your own seat'
            using errcode = '42501';
    end if;

    return new;
end;
$$;

drop trigger if exists open_tables_guard_update on public.open_tables;
create trigger open_tables_guard_update
    before update on public.open_tables
    for each row execute function public.open_tables_guard_update();

-- ---------------------------------------------------------------------------
-- Visibility: live state is for people at the table; joiners get a preview
-- ---------------------------------------------------------------------------

drop policy if exists "open_tables_select_authenticated" on public.open_tables;
drop policy if exists "open_tables_select_authorized" on public.open_tables;
create policy "open_tables_select_authorized"
    on public.open_tables for select to authenticated
    using (
        host_user_id = auth.uid()
        or public.open_table_holds_seat(seats, coalesce(auth.uid()::text, ''))
    );

-- Row-level security cannot tell "taking an empty seat" from "rewriting
-- somebody else's" because it only sees one version of the row. The trigger
-- sees both, so it is where those rules live. Guests sit and stand through
-- the seat RPCs; a direct update that breaks the rules is raised there.
drop policy if exists "open_tables_update_authenticated" on public.open_tables;
drop policy if exists "open_tables_update_guarded" on public.open_tables;
create policy "open_tables_update_guarded"
    on public.open_tables for update to authenticated using (true);

create or replace function public.open_table_preview(p_invite_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    code text := upper(trim(p_invite_code));
    tbl public.open_tables;
    seats jsonb := '[]'::jsonb;
    item jsonb;
begin
    perform public.vault_require_user();

    select * into tbl from public.open_tables where invite_code = code;
    if not found then
        return null;
    end if;

    for item in select value from jsonb_array_elements(coalesce(tbl.seats, '[]'::jsonb))
    loop
        seats := seats || jsonb_build_array(jsonb_build_object(
            'id', item->>'id',
            'seatNumber', nullif(item->>'seatNumber', '')::int,
            'playerName', coalesce(item->>'playerName', 'Player'),
            'playerKey', item->>'playerKey',
            'amount', '0',
            'isHost', coalesce((item->>'isHost')::boolean, false)
        ));
    end loop;

    return jsonb_build_object(
        'id', tbl.id,
        'invite_code', tbl.invite_code,
        'host_user_id', tbl.host_user_id,
        'host_display_name', tbl.host_display_name,
        'host_player_key', tbl.host_player_key,
        'session_currency_code', tbl.session_currency_code,
        'is_started', tbl.is_started,
        'ante_amount', tbl.ante_amount,
        'seats', seats,
        'created_at', tbl.created_at,
        'updated_at', tbl.updated_at
    );
end;
$$;

revoke all on function public.open_table_preview(text) from public, anon;
grant execute on function public.open_table_preview(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Seat RPCs run as the owner so a joiner can sit without reading the live row
-- ---------------------------------------------------------------------------

create or replace function public.merge_open_table_seat(
    p_invite_code text,
    p_seat jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    normalized_code text := upper(trim(p_invite_code));
    caller text := public.open_table_seat_key();
    seat_number integer := nullif(p_seat->>'seatNumber', '')::integer;
    current_seats jsonb;
    next_seats jsonb := '[]'::jsonb;
    existing_seat jsonb;
    merged_seat jsonb;
    table_host_key text;
    item jsonb;
    stake_cents bigint;
begin
    if caller = '' then
        raise exception 'Not authenticated';
    end if;

    if seat_number is null or seat_number < 1 or seat_number > 8 then
        raise exception 'invalid seat';
    end if;

    select seats, host_player_key
    into current_seats, table_host_key
    from public.open_tables
    where invite_code = normalized_code
    for update;

    if not found then
        raise exception 'table not found';
    end if;

    for item in select value from jsonb_array_elements(coalesce(current_seats, '[]'::jsonb))
    loop
        if item->>'playerKey' = caller then
            existing_seat := item;
            continue;
        end if;
        if nullif(item->>'seatNumber', '')::integer = seat_number then
            raise exception 'seat taken';
        end if;
        next_seats := next_seats || jsonb_build_array(item);
    end loop;

    merged_seat := coalesce(existing_seat, '{}'::jsonb) || p_seat || jsonb_build_object(
        'id', coalesce(existing_seat->>'id', p_seat->>'id', gen_random_uuid()::text),
        'playerKey', caller,
        'seatNumber', seat_number,
        'isHost', coalesce(table_host_key = caller, false)
    );

    select s.in_play_cents into stake_cents
    from public.vault_table_stakes s
    where s.invite_code = normalized_code
      and s.player_key = caller
      and s.status = 'seated';
    if found then
        merged_seat := merged_seat || jsonb_build_object(
            'amount', public.poker_cents_text(stake_cents)
        );
    end if;

    next_seats := next_seats || jsonb_build_array(merged_seat);

    update public.open_tables
    set seats = next_seats,
        updated_at = now()
    where invite_code = normalized_code;

    return next_seats;
end;
$$;

revoke all on function public.merge_open_table_seat(text, jsonb) from public, anon;
grant execute on function public.merge_open_table_seat(text, jsonb) to authenticated;

create or replace function public.remove_open_table_seat(p_invite_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    normalized_code text := upper(trim(p_invite_code));
    caller text := public.open_table_seat_key();
    current_seats jsonb;
    next_seats jsonb := '[]'::jsonb;
    item jsonb;
begin
    if caller = '' then
        raise exception 'Not authenticated';
    end if;

    select seats into current_seats
    from public.open_tables
    where invite_code = normalized_code
    for update;

    if not found then
        raise exception 'table not found';
    end if;

    for item in select value from jsonb_array_elements(coalesce(current_seats, '[]'::jsonb))
    loop
        if item->>'playerKey' = caller then
            continue;
        end if;
        next_seats := next_seats || jsonb_build_array(item);
    end loop;

    update public.open_tables
    set seats = next_seats,
        updated_at = now()
    where invite_code = normalized_code;

    return next_seats;
end;
$$;

revoke all on function public.remove_open_table_seat(text) from public, anon;
grant execute on function public.remove_open_table_seat(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Register the table in the table's own currency. Client p_currency is ignored.
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
    real_host uuid;
    table_currency text;
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

    select coalesce(nullif(trim(session_currency_code), ''), 'USD')
    into table_currency
    from public.open_tables
    where invite_code = code;

    -- p_currency is accepted so older clients keep working, then ignored.
    -- Settlement is always integer cents of the table's session currency.
    if p_currency is not null then
        null;
    end if;

    select * into existing from public.vault_tables where invite_code = code for update;

    if not found then
        insert into public.vault_tables (
            invite_code, host_user_id, currency_code,
            min_buy_in_cents, max_buy_in_cents, is_demo
        )
        values (code, real_host, table_currency, p_min_buy_in_cents, p_max_buy_in_cents,
                public.vault_is_sandbox())
        returning * into row_out;

        perform public.vault_log(uid, 'table_registered', 'ok', null, null, code,
                                 jsonb_build_object('currency', table_currency));
        return row_out;
    end if;

    if existing.host_user_id <> real_host then
        update public.vault_tables
        set host_user_id = real_host, updated_at = now()
        where invite_code = code;

        perform public.vault_log(uid, 'table_host_corrected', 'ok', null, null, code,
                                 jsonb_build_object('was', existing.host_user_id, 'now', real_host));
    end if;

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
        updated_at = now()
    where invite_code = code
    returning * into row_out;

    return row_out;
end;
$$;

revoke all on function public.vault_register_table(text, bigint, bigint, text) from public, anon;
grant execute on function public.vault_register_table(text, bigint, bigint, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Leave: fold from poker_hands, never from a phone-written JSON blob
-- ---------------------------------------------------------------------------

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
begin
    return exists (
        select 1
        from public.poker_hands h
        join public.poker_hand_seats s on s.hand_id = h.id
        where h.invite_code = upper(trim(p_invite_code))
          and not h.is_complete
          and s.player_key = p_player_key
          and not s.is_folded
    );
end;
$$;

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
    withheld bigint := 0;
    return_cents bigint;
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

    -- Apply a pending timeout first so a disconnected actor cannot leave
    -- with chips they were about to lose to the clock.
    perform public.poker_sweep_timeouts(code);

    -- Fold from the server hand. open_tables.hand is not consulted.
    -- If that ends the hand the pot is paid immediately and nothing is
    -- withheld. If the hand goes on, committed chips stay in play.
    withheld := public.poker_withdraw_player(code, stake.player_key);
    withheld := public.poker_live_committed_cents(code, stake.player_key);

    in_play := public.vault_account(uid, 'in_play', tbl.currency_code, code);
    available := public.vault_account(uid, 'available', tbl.currency_code);

    select balance_cents into final_cents
    from public.vault_accounts where id = in_play for update;

    if withheld > final_cents then
        withheld := final_cents;
    end if;
    return_cents := final_cents - withheld;
    bought_in := stake.total_bought_in_cents;

    if return_cents > 0 then
        posted := public.vault_post_transaction(
            uid, 'table_return',
            jsonb_build_array(
                jsonb_build_object('account_id', in_play, 'amount_cents', -return_cents),
                jsonb_build_object('account_id', available, 'amount_cents', return_cents)
            ),
            p_idempotency_key, code,
            jsonb_build_object('bought_in_cents', bought_in, 'withheld_cents', withheld)
        );

        perform public.vault_add_statement(
            uid, 'table_return', 'completed', 0, tbl.currency_code,
            posted.id, null, null, code, 'Returned from the table to your Vault'
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
                             jsonb_build_object('withheld_cents', withheld));

    return jsonb_build_object(
        'invite_code', code,
        'bought_in_cents', bought_in,
        'returned_cents', return_cents,
        'net_cents', return_cents - bought_in,
        'reference_code', coalesce(posted.reference_code, ''),
        'already_settled', false
    );
end;
$$;

revoke all on function public.vault_leave_table(text, text) from public, anon;
grant execute on function public.vault_leave_table(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Disconnect / timeout: fold the actor whose deadline has passed
-- ---------------------------------------------------------------------------

create or replace function public.poker_sweep_timeouts(p_invite_code text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    uid uuid := public.vault_require_user();
    code text := upper(trim(p_invite_code));
    hand public.poker_hands;
    actor public.poker_hand_seats;
    action_key text;
    authorized boolean;
begin
    authorized := public.open_table_is_authorized(code)
        or exists (
            select 1 from public.vault_table_stakes
            where invite_code = code and user_id = uid
        );
    if not authorized then
        raise exception 'poker: you are not at that table' using errcode = '42501';
    end if;

    select * into hand
    from public.poker_hands
    where invite_code = code and not is_complete
    for update;
    if not found then
        return public.poker_hand_snapshot(
            (select id from public.poker_hands
             where invite_code = code
             order by hand_number desc limit 1),
            uid::text
        );
    end if;

    if hand.acting_seat is null
       or hand.action_deadline is null
       or hand.action_deadline > clock_timestamp() then
        return public.poker_hand_snapshot(hand.id, uid::text);
    end if;

    select * into actor
    from public.poker_hand_seats
    where hand_id = hand.id and seat_number = hand.acting_seat
    for update;
    if not found or actor.is_folded then
        return public.poker_hand_snapshot(hand.id, uid::text);
    end if;

    action_key := 'timeout:' || hand.id::text || ':' || hand.revision::text;

    if exists (
        select 1 from public.poker_hand_actions
        where hand_id = hand.id and action_id = action_key
    ) then
        return public.poker_hand_snapshot(hand.id, uid::text);
    end if;

    perform public.poker_apply_action(hand.id, actor.player_key, 'fold', null);

    insert into public.poker_hand_actions (
        hand_id, action_id, player_key, action, amount_cents, revision
    )
    select hand.id, action_key, actor.player_key, 'fold', null, h.revision
    from public.poker_hands h where h.id = hand.id;

    perform public.poker_publish_snapshot(hand.id);
    return public.poker_hand_snapshot(hand.id, uid::text);
end;
$$;

revoke all on function public.poker_sweep_timeouts(text) from public, anon;
grant execute on function public.poker_sweep_timeouts(text) to authenticated;

-- Looking at the table applies any pending timeout so a disconnected player
-- cannot hold the game open. Hole cards stay viewer-scoped.
create or replace function public.poker_hand_view(p_invite_code text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    uid uuid := public.vault_require_user();
    code text := upper(trim(p_invite_code));
begin
    if not public.open_table_is_authorized(code) then
        raise exception 'poker: you are not at that table' using errcode = '42501';
    end if;

    return public.poker_sweep_timeouts(code);
end;
$$;

revoke all on function public.poker_hand_view(text) from public, anon;
grant execute on function public.poker_hand_view(text) to authenticated;

create or replace function public.poker_act(
    p_invite_code text,
    p_action text,
    p_amount_cents bigint default null,
    p_action_id text default null
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
    hand public.poker_hands;
    action_key text := nullif(trim(coalesce(p_action_id, '')), '');
    existing public.poker_hand_actions;
begin
    if action_key is null then
        raise exception 'poker: every action needs an action id' using errcode = '22023';
    end if;

    -- A late action after the clock has run is a fold, not a bet.
    perform public.poker_sweep_timeouts(code);

    select * into hand
    from public.poker_hands
    where invite_code = code and not is_complete
    for update;
    if not found then
        raise exception 'poker: there is no hand in progress' using errcode = 'P0002';
    end if;

    select * into existing
    from public.poker_hand_actions
    where hand_id = hand.id and action_id = action_key;
    if found then
        return public.poker_hand_snapshot(hand.id, uid::text);
    end if;

    perform public.poker_apply_action(hand.id, uid::text, p_action, p_amount_cents);

    insert into public.poker_hand_actions (
        hand_id, action_id, player_key, action, amount_cents, revision
    )
    select hand.id, action_key, uid::text, lower(trim(p_action)), p_amount_cents, h.revision
    from public.poker_hands h where h.id = hand.id;

    perform public.poker_publish_snapshot(hand.id);
    return public.poker_hand_snapshot(hand.id, uid::text);
end;
$$;

revoke all on function public.poker_act(text, text, bigint, text) from public, anon;
grant execute on function public.poker_act(text, text, bigint, text) to authenticated;

-- Snapshot includes the server deadline so phones can show a clock. They
-- cannot set it, and they cannot use it to fold anyone themselves.
create or replace function public.poker_hand_snapshot(p_hand_id uuid, p_viewer_key text default null)
returns jsonb
language plpgsql
stable
as $$
declare
    hand public.poker_hands;
    seats jsonb := '[]'::jsonb;
    rec public.poker_hand_seats;
    seat_json jsonb;
begin
    if p_hand_id is null then
        return null;
    end if;

    select * into hand from public.poker_hands where id = p_hand_id;
    if not found then
        return null;
    end if;

    for rec in
        select * from public.poker_hand_seats
        where hand_id = p_hand_id
        order by seat_number
    loop
        seat_json := public.poker_public_seat(rec, hand.is_revealed);
        if p_viewer_key is not null and rec.player_key = p_viewer_key then
            seat_json := jsonb_set(seat_json, '{cards}', rec.hole_cards);
        end if;
        seats := seats || jsonb_build_array(seat_json);
    end loop;

    return jsonb_build_object(
        'id', hand.id,
        'version', 3,
        'handNumber', hand.hand_number,
        'revision', hand.revision,
        'dealerSeat', hand.dealer_seat,
        'ante', public.poker_cents_text(hand.ante_cents),
        'street', hand.street,
        'board', hand.board,
        'deck', '[]'::jsonb,
        'actingSeat', hand.acting_seat,
        'actionDeadline', hand.action_deadline,
        'isComplete', hand.is_complete,
        'isRevealed', hand.is_revealed,
        'winnerSeats', to_jsonb(hand.winner_seats),
        'resultSummary', hand.result_summary,
        'seats', seats
    );
end;
$$;

create or replace function public.poker_start_hand_internal(
    p_invite_code text,
    p_deck jsonb default null
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
    tbl_row public.open_tables;
    live public.poker_hands;
    players_count int := 0;
    dealer int;
    prev_dealer int;
    v_hand_id uuid := gen_random_uuid();
    hand_no int;
    ante bigint;
    deck jsonb;
    order_seats integer[];
    seat_no int;
    card text;
    pass int;
    first_actor int;
begin
    if code = '' then
        raise exception 'poker: unknown table' using errcode = 'P0002';
    end if;

    select * into tbl_row from public.open_tables where invite_code = code for update;
    if not found then
        raise exception 'poker: unknown table' using errcode = 'P0002';
    end if;

    if not exists (
        select 1
        from jsonb_array_elements(coalesce(tbl_row.seats, '[]'::jsonb)) seat
        where seat->>'playerKey' = uid::text
    ) then
        raise exception 'poker: you are not at that table' using errcode = '42501';
    end if;

    perform public.poker_sweep_timeouts(code);

    select * into live
    from public.poker_hands
    where invite_code = code and not is_complete
    for update;
    if found then
        return public.poker_hand_snapshot(live.id, uid::text);
    end if;

    create temporary table if not exists poker_start_players (
        user_id uuid,
        player_key text,
        seat_number int,
        player_name text,
        stack_cents bigint,
        is_host boolean
    ) on commit drop;
    delete from poker_start_players;

    insert into poker_start_players (user_id, player_key, seat_number, player_name, stack_cents, is_host)
    select s.user_id,
           s.player_key,
           nullif(seat->>'seatNumber', '')::int,
           coalesce(nullif(seat->>'playerName', ''), s.display_name, 'Player'),
           s.in_play_cents,
           coalesce((seat->>'isHost')::boolean, tbl_row.host_user_id = s.user_id)
    from public.vault_table_stakes s
    join jsonb_array_elements(coalesce(tbl_row.seats, '[]'::jsonb)) seat
      on seat->>'playerKey' = s.player_key
    where s.invite_code = code
      and s.status = 'seated'
      and s.in_play_cents > 0
      and nullif(seat->>'seatNumber', '')::int between 1 and 8;

    select count(*) into players_count from poker_start_players;
    if players_count < 2 then
        raise exception 'poker: two players need money on the table to deal a hand'
            using errcode = 'P0002';
    end if;

    select dealer_seat into prev_dealer
    from public.poker_hands
    where invite_code = code
    order by hand_number desc
    limit 1;

    if prev_dealer is not null then
        dealer := (
            public.poker_action_order(
                array(select seat_number from poker_start_players),
                prev_dealer
            )
        )[1];
    else
        select seat_number into dealer
        from poker_start_players
        where is_host
        order by seat_number
        limit 1;
        if dealer is null then
            select min(seat_number) into dealer from poker_start_players;
        end if;
    end if;

    select coalesce(max(hand_number), 0) + 1 into hand_no
    from public.poker_hands where invite_code = code;

    ante := public.poker_ante_cents(tbl_row.ante_amount);
    if p_deck is null or jsonb_array_length(p_deck) = 0 then
        deck := public.poker_shuffle_deck(public.poker_full_deck());
    else
        deck := p_deck;
        -- Append any missing cards so a stacked test deck still has a board.
        -- The column cannot be named `card` — that is a PL/pgSQL variable here.
        deck := deck || coalesce((
            select jsonb_agg(remaining)
            from jsonb_array_elements_text(public.poker_full_deck()) as remaining
            where not exists (
                select 1
                from jsonb_array_elements_text(p_deck) as dealt
                where dealt = remaining
            )
        ), '[]'::jsonb);
    end if;

    insert into public.poker_hands (
        id, invite_code, hand_number, revision, dealer_seat, ante_cents, deck
    ) values (
        v_hand_id, code, hand_no, 1, dealer, ante, deck
    );

    insert into public.poker_hand_seats (
        hand_id, user_id, player_key, seat_number, player_name, stack_cents
    )
    select v_hand_id, user_id, player_key, seat_number, player_name, stack_cents
    from poker_start_players;

    select public.poker_action_order(array_agg(seat_number), dealer)
    into order_seats
    from public.poker_hand_seats
    where poker_hand_seats.hand_id = v_hand_id;

    for pass in 1..2 loop
        foreach seat_no in array order_seats loop
            card := public.poker_draw_card(v_hand_id);
            update public.poker_hand_seats
            set hole_cards = hole_cards || jsonb_build_array(card)
            where poker_hand_seats.hand_id = v_hand_id and seat_number = seat_no;
        end loop;
    end loop;

    first_actor := public.poker_first_to_act(v_hand_id);
    update public.poker_hands
    set acting_seat = first_actor, updated_at = now()
    where id = v_hand_id;
    if first_actor is null then
        perform public.poker_close_street(v_hand_id);
    end if;

    perform public.poker_publish_snapshot(v_hand_id);
    return public.poker_hand_snapshot(v_hand_id, uid::text);
end;
$$;

revoke all on function public.poker_start_hand_internal(text, jsonb) from public, anon, authenticated;

create or replace function public.poker_start_hand(p_invite_code text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
    -- Fold anyone whose clock has run so a disconnected player cannot
    -- block the next deal. Clients still cannot pass a deck.
    if public.open_table_is_authorized(p_invite_code) then
        perform public.poker_sweep_timeouts(p_invite_code);
    end if;
    return public.poker_start_hand_internal(p_invite_code, null);
end;
$$;

revoke all on function public.poker_start_hand(text) from public, anon;
grant execute on function public.poker_start_hand(text) to authenticated;

notify pgrst, 'reload schema';
