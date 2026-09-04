-- Pre-flop hands on a shared table: the ante everyone posts to stay in,
-- and the round that goes seat by seat asking who is in the hand.

alter table public.open_tables
    add column if not exists ante_amount text not null default '0';

alter table public.open_tables
    add column if not exists hand jsonb;
