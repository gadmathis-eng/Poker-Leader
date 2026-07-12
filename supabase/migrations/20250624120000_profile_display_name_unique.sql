alter table public.profiles
    add column if not exists display_name_lower text;

update public.profiles
set display_name_lower = lower(trim(display_name))
where display_name_lower is null;

alter table public.profiles
    alter column display_name_lower set not null;

create unique index if not exists profiles_display_name_lower_key
    on public.profiles (display_name_lower);
