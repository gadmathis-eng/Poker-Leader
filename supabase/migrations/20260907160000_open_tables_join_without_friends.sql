-- Anyone signed in can join an open table with the invite code or share link.
-- An accepted friend request is not required.
--
-- Paste this file into the Supabase SQL Editor after
-- supabase/migrations/20260904120000_open_tables.sql if that table already exists.

drop policy if exists "open_tables_select_friends" on public.open_tables;
drop policy if exists "open_tables_select_host_or_friends" on public.open_tables;
drop policy if exists "open_tables_update_friends" on public.open_tables;
drop policy if exists "open_tables_update_host_or_friends" on public.open_tables;

drop policy if exists "open_tables_select_authenticated" on public.open_tables;
create policy "open_tables_select_authenticated"
    on public.open_tables for select to authenticated using (true);

drop policy if exists "open_tables_update_authenticated" on public.open_tables;
create policy "open_tables_update_authenticated"
    on public.open_tables for update to authenticated
    using (true)
    with check (true);

comment on table public.open_tables is
    'Live tables. Anyone signed in can join with the invite code or share link; friendship is not required.';

comment on function public.merge_open_table_seat(text, jsonb) is
    'Seats one player by invite code. Does not check friend_requests.';

notify pgrst, 'reload schema';
