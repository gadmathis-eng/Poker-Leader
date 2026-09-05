-- Shareable open tables that friends can join from a tapable link or a 6-character code.
--
-- If the app shows:
--   Could not find the table 'public.open_tables' in the schema cache
-- paste this entire file into the Supabase SQL Editor and click Run.

create table if not exists public.open_tables (
    id uuid primary key,
    invite_code text not null unique,
    host_user_id uuid not null references auth.users (id) on delete cascade,
    host_display_name text not null,
    host_player_key text not null,
    session_currency_code text not null default 'GBP',
    is_started boolean not null default false,
    seats jsonb not null default '[]'::jsonb,
    ante_amount text not null default '0',
    hand jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists open_tables_invite_code_idx on public.open_tables (invite_code);
create index if not exists open_tables_host_user_id_idx on public.open_tables (host_user_id);

alter table public.open_tables enable row level security;

grant usage on schema public to anon, authenticated, service_role;
grant select, insert, update, delete on table public.open_tables to anon, authenticated, service_role;

drop policy if exists "open_tables_select_authenticated" on public.open_tables;
create policy "open_tables_select_authenticated"
    on public.open_tables for select to authenticated using (true);

drop policy if exists "open_tables_insert_host" on public.open_tables;
create policy "open_tables_insert_host"
    on public.open_tables for insert to authenticated
    with check (auth.uid() = host_user_id);

drop policy if exists "open_tables_update_authenticated" on public.open_tables;
create policy "open_tables_update_authenticated"
    on public.open_tables for update to authenticated using (true);

drop policy if exists "open_tables_delete_host" on public.open_tables;
create policy "open_tables_delete_host"
    on public.open_tables for delete to authenticated
    using (auth.uid() = host_user_id);

-- Merge one player's seat under a row lock so two devices cannot overwrite each other.
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
    player_key text := p_seat->>'playerKey';
    seat_number integer := nullif(p_seat->>'seatNumber', '')::integer;
    current_seats jsonb;
    next_seats jsonb := '[]'::jsonb;
    item jsonb;
begin
    if auth.uid() is null then
        raise exception 'Not authenticated';
    end if;

    if player_key is null or player_key = '' or seat_number is null or seat_number < 1 or seat_number > 8 then
        raise exception 'invalid seat';
    end if;

    select seats
    into current_seats
    from public.open_tables
    where invite_code = normalized_code
    for update;

    if not found then
        raise exception 'table not found';
    end if;

    for item in select value from jsonb_array_elements(coalesce(current_seats, '[]'::jsonb))
    loop
        if item->>'playerKey' = player_key then
            continue;
        end if;
        if nullif(item->>'seatNumber', '')::integer = seat_number then
            raise exception 'seat taken';
        end if;
        next_seats := next_seats || jsonb_build_array(item);
    end loop;

    next_seats := next_seats || jsonb_build_array(p_seat);

    update public.open_tables
    set seats = next_seats,
        updated_at = now()
    where invite_code = normalized_code;

    return next_seats;
end;
$$;

revoke all on function public.merge_open_table_seat(text, jsonb) from public;
grant execute on function public.merge_open_table_seat(text, jsonb) to authenticated;

do $$
begin
    if not exists (
        select 1
        from pg_publication_rel rel
        join pg_publication pub on pub.oid = rel.prpubid
        join pg_class cls on cls.oid = rel.prrelid
        join pg_namespace nsp on nsp.oid = cls.relnamespace
        where pub.pubname = 'supabase_realtime'
          and nsp.nspname = 'public'
          and cls.relname = 'open_tables'
    ) then
        alter publication supabase_realtime add table public.open_tables;
    end if;
exception
    when undefined_object then
        null;
end;
$$;

-- Idempotent if this file is pasted again after the table already exists.
alter table public.open_tables
    add column if not exists ante_amount text not null default '0';

alter table public.open_tables
    add column if not exists hand jsonb;

notify pgrst, 'reload schema';
