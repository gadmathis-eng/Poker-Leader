-- Shareable open tables that friends can join from a tapable link.

create table if not exists public.open_tables (
    id uuid primary key,
    invite_code text not null unique,
    host_user_id uuid not null references auth.users (id) on delete cascade,
    host_display_name text not null,
    host_player_key text not null,
    session_currency_code text not null default 'GBP',
    is_started boolean not null default false,
    seats jsonb not null default '[]'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists open_tables_invite_code_idx on public.open_tables (invite_code);
create index if not exists open_tables_host_user_id_idx on public.open_tables (host_user_id);

alter table public.open_tables enable row level security;

create policy "open_tables_select_authenticated"
    on public.open_tables for select to authenticated using (true);

create policy "open_tables_insert_host"
    on public.open_tables for insert to authenticated
    with check (auth.uid() = host_user_id);

create policy "open_tables_update_authenticated"
    on public.open_tables for update to authenticated using (true);

create policy "open_tables_delete_host"
    on public.open_tables for delete to authenticated
    using (auth.uid() = host_user_id);
