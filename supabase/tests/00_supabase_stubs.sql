-- Minimal stand-ins for the pieces of Supabase the migration leans on, so the
-- vault migration can be loaded and exercised on a plain PostgreSQL server.
create extension if not exists "pgcrypto";

create schema if not exists auth;

create table if not exists auth.users (
    id uuid primary key default gen_random_uuid(),
    email text
);

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
    select nullif(current_setting('test.uid', true), '')::uuid;
$$;

do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'service_role') then
        create role service_role nologin;
    end if;
end;
$$;
