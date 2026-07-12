-- Pot Master / PokerLeader initial Supabase schema
-- Run in Supabase SQL Editor or via: supabase db push

create extension if not exists "pgcrypto";

create table if not exists public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    handle text not null,
    handle_lower text not null unique,
    display_name text not null,
    updated_at timestamptz not null default now()
);

create table if not exists public.circles (
    id uuid primary key,
    owner_user_id uuid references auth.users (id) on delete set null,
    name text not null,
    short_code text not null unique,
    default_buy_in text not null default '20',
    currency_code text not null default 'GBP',
    member_count integer not null default 0,
    game_count integer not null default 0,
    created_at timestamptz not null default now(),
    last_played_at timestamptz,
    updated_at timestamptz not null default now()
);

create index if not exists circles_short_code_idx on public.circles (short_code);

create table if not exists public.circle_members (
    id uuid primary key,
    circle_id uuid not null references public.circles (id) on delete cascade,
    user_id uuid references auth.users (id) on delete set null,
    display_name text not null,
    initial text not null,
    handle text,
    is_current_user boolean not null default false,
    joined_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists circle_members_circle_id_idx on public.circle_members (circle_id);

create table if not exists public.sessions (
    id uuid primary key,
    circle_id uuid not null references public.circles (id) on delete cascade,
    title text not null,
    status text not null,
    buy_in_amount text not null,
    currency_code text not null,
    pot_total text not null,
    started_at timestamptz,
    ended_at timestamptz,
    summary_line text,
    players jsonb not null default '[]'::jsonb,
    payments jsonb not null default '[]'::jsonb,
    updated_at timestamptz not null default now()
);

create index if not exists sessions_circle_id_idx on public.sessions (circle_id);

create table if not exists public.friend_requests (
    id uuid primary key default gen_random_uuid(),
    from_user_id uuid not null references auth.users (id) on delete cascade,
    from_handle text not null,
    from_display_name text not null,
    to_user_id uuid not null references auth.users (id) on delete cascade,
    to_handle text not null,
    status text not null default 'pending',
    created_at timestamptz not null default now(),
    responded_at timestamptz
);

create index if not exists friend_requests_to_user_status_idx
    on public.friend_requests (to_user_id, status);

alter table public.profiles enable row level security;
alter table public.circles enable row level security;
alter table public.circle_members enable row level security;
alter table public.sessions enable row level security;
alter table public.friend_requests enable row level security;

create policy "profiles_select_authenticated"
    on public.profiles for select to authenticated using (true);

create policy "profiles_insert_own"
    on public.profiles for insert to authenticated with check (auth.uid() = id);

create policy "profiles_update_own"
    on public.profiles for update to authenticated using (auth.uid() = id);

create policy "circles_select_authenticated"
    on public.circles for select to authenticated using (true);

create policy "circles_insert_authenticated"
    on public.circles for insert to authenticated with check (auth.uid() = owner_user_id);

create policy "circles_update_authenticated"
    on public.circles for update to authenticated using (true);

create policy "circle_members_select_authenticated"
    on public.circle_members for select to authenticated using (true);

create policy "circle_members_insert_authenticated"
    on public.circle_members for insert to authenticated with check (true);

create policy "circle_members_update_authenticated"
    on public.circle_members for update to authenticated using (true);

create policy "sessions_select_authenticated"
    on public.sessions for select to authenticated using (true);

create policy "sessions_insert_authenticated"
    on public.sessions for insert to authenticated with check (true);

create policy "sessions_update_authenticated"
    on public.sessions for update to authenticated using (true);

create policy "friend_requests_select_participants"
    on public.friend_requests for select to authenticated
    using (auth.uid() = from_user_id or auth.uid() = to_user_id);

create policy "friend_requests_insert_sender"
    on public.friend_requests for insert to authenticated
    with check (auth.uid() = from_user_id);

create policy "friend_requests_update_recipient"
    on public.friend_requests for update to authenticated
    using (auth.uid() = to_user_id);
