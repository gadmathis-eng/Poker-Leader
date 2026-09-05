-- Optional dedicated columns for the ante and the hand in progress.
-- The app also packs those into the existing seats JSON, so a live project
-- that already has open_tables shares a hand without running this file.
--
-- Paste this entire file into the Supabase SQL Editor and click Run if you
-- want separate columns instead of the packed seats fallback.

alter table public.open_tables
    add column if not exists ante_amount text not null default '0';

alter table public.open_tables
    add column if not exists hand jsonb;

notify pgrst, 'reload schema';
