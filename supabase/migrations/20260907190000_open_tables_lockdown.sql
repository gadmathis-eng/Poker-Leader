-- Pot Master — stop players writing over each other's shared table state.
--
-- Paste this whole file into the Supabase SQL Editor and click Run, after
-- 20260904120000_open_tables.sql. It is safe to run more than once.
--
-- `open_tables` carries the state two phones share while a table is being
-- played: who is seated, what they are sitting with, the ante, and the hand in
-- progress. Its update policy was `using (true)` — any signed-in user in the
-- whole system could rewrite any table's row, whether or not they were at it.
-- `merge_open_table_seat` was no better: it read `playerKey` out of the
-- submitted JSON and never checked it belonged to the caller, so one request
-- could move another player's seat or restate their chips.
--
-- WHAT IS ENFORCED NOW
--   * The columns that say which table this is and who hosts it cannot be
--     changed by anybody.
--   * The table's name, currency, ante and started flag are the host's alone.
--   * A player may only add, change or remove THEIR OWN seat. Every other seat
--     must come back byte-identical.
--   * The hand in progress may only be written by someone actually seated.
--
-- WHAT IS NOT, AND CANNOT BE UNTIL THE SERVER RUNS THE GAME
--   The hand itself — the cards, the pot, whose turn it is — is still written by
--   the players' phones, because in this architecture the shared row *is* the
--   game and every player has to be able to advance it. A player seated at a
--   table can therefore still publish a dishonest hand. Locking that down means
--   the server dealing the deck, taking the bets and deciding the winner, which
--   is a separate piece of work. Until then, treat the hand column as agreed
--   between participants rather than verified.
--
--   Reads are also still open to any signed-in user who knows the six-character
--   code, because that is how joining works: you have to be able to read a table
--   before you have a seat at it. The code is the secret.

-- ---------------------------------------------------------------------------
-- Is the caller at this table?
-- ---------------------------------------------------------------------------
-- A signed-in player's seat key is their account id, which is what the app
-- already sends. Matching on it here means the answer comes from the JWT.

create or replace function public.open_table_seat_key()
returns text
language sql
stable
as $$
    select coalesce(auth.uid()::text, '');
$$;

create or replace function public.open_table_holds_seat(p_seats jsonb, p_key text)
returns boolean
language sql
immutable
as $$
    select p_key <> '' and exists (
        select 1
        from jsonb_array_elements(coalesce(p_seats, '[]'::jsonb)) seat
        where seat->>'playerKey' = p_key
    );
$$;

-- Every seat except the caller's, keyed by player, so two versions of the seat
-- list can be compared while ignoring the one seat the caller is allowed to
-- touch. A seat with no player key is keyed by its position so it cannot be
-- silently dropped.
create or replace function public.open_table_other_seats(p_seats jsonb, p_key text)
returns jsonb
language sql
immutable
as $$
    select coalesce(
        jsonb_object_agg(
            coalesce(nullif(seat.value->>'playerKey', ''), '#' || seat.ordinality::text),
            seat.value
        ),
        '{}'::jsonb
    )
    from jsonb_array_elements(coalesce(p_seats, '[]'::jsonb)) with ordinality as seat(value, ordinality)
    where coalesce(seat.value->>'playerKey', '') <> p_key;
$$;

-- ---------------------------------------------------------------------------
-- The guard
-- ---------------------------------------------------------------------------

create or replace function public.open_tables_guard_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    caller text := public.open_table_seat_key();
    is_host boolean;
    was_seated boolean;
    is_seated boolean;
begin
    -- No `auth.uid()` means this is `service_role` or a migration, not a player.
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

    is_host := old.host_user_id::text = caller;
    if is_host then
        return new;
    end if;

    if new.session_currency_code <> old.session_currency_code
       or new.ante_amount <> old.ante_amount
       or new.is_started <> old.is_started
       or coalesce(new.host_display_name, '') <> coalesce(old.host_display_name, '')
       or coalesce(new.host_player_key, '') <> coalesce(old.host_player_key, '') then
        raise exception 'open_tables: only the host can change this table''s settings'
            using errcode = '42501';
    end if;

    if public.open_table_other_seats(new.seats, caller)
       <> public.open_table_other_seats(old.seats, caller) then
        raise exception 'open_tables: you can only change your own seat'
            using errcode = '42501';
    end if;

    was_seated := public.open_table_holds_seat(old.seats, caller);
    is_seated := public.open_table_holds_seat(new.seats, caller);

    if new.hand is distinct from old.hand and not (was_seated or is_seated) then
        raise exception 'open_tables: you are not at that table'
            using errcode = '42501';
    end if;

    return new;
end;
$$;

drop trigger if exists open_tables_guard_update on public.open_tables;
create trigger open_tables_guard_update
    before update on public.open_tables
    for each row execute function public.open_tables_guard_update();

-- The policy stays open to signed-in users on purpose: row-level security is
-- evaluated against the row as it was, so a policy alone cannot tell "taking an
-- empty seat" from "rewriting somebody else's". The trigger above can see both
-- versions of the row, so that is where the rules live. Named for what it now
-- means.
drop policy if exists "open_tables_update_authenticated" on public.open_tables;
drop policy if exists "open_tables_update_guarded" on public.open_tables;
create policy "open_tables_update_guarded"
    on public.open_tables for update to authenticated using (true);

-- Anonymous users were granted write access alongside `authenticated` in the
-- original migration. Nothing in the app signs in anonymously to play, and an
-- unauthenticated caller has no `auth.uid()` for the guard to check, so they are
-- taken off the table entirely.
revoke insert, update, delete on table public.open_tables from anon;

-- ---------------------------------------------------------------------------
-- FIX 3 — merge_open_table_seat: the seat is the caller's, whatever they send
-- ---------------------------------------------------------------------------
-- The seat's player key, host flag and display identity are now set from
-- `auth.uid()` and from the table row. Only the seat number, the name shown and
-- the amount come from the request, and the amount is display state — the Vault
-- ledger, not this column, decides what a player actually has in play.

create or replace function public.merge_open_table_seat(
    p_invite_code text,
    p_seat jsonb
)
returns jsonb
language plpgsql
security invoker
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

    -- Built from the caller's identity rather than copied from the request, so a
    -- doctored payload cannot claim another player's seat or the host's chair.
    merged_seat := coalesce(existing_seat, '{}'::jsonb) || p_seat || jsonb_build_object(
        'id', coalesce(existing_seat->>'id', p_seat->>'id', gen_random_uuid()::text),
        'playerKey', caller,
        'seatNumber', seat_number,
        'isHost', coalesce(table_host_key = caller, false)
    );

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

-- Standing up, without sending the seat list. A guest used to publish the whole
-- array to drop their own row, which meant sending back a copy of everybody
-- else's seats — and a stale copy would now be refused by the guard. Removing
-- one seat server-side is both safer and less fragile.
create or replace function public.remove_open_table_seat(p_invite_code text)
returns jsonb
language plpgsql
security invoker
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

notify pgrst, 'reload schema';
