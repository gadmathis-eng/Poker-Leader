-- Pre-flop hands on a shared table: the ante everyone posts to stay in,
-- and the round that goes seat by seat asking who is in the hand.
--
-- If the app shows:
--   Could not find the 'hand' column of 'open_tables' in the schema cache
-- paste this entire file into the Supabase SQL Editor and click Run.

alter table public.open_tables
    add column if not exists ante_amount text not null default '0';

alter table public.open_tables
    add column if not exists hand jsonb;

notify pgrst, 'reload schema';
