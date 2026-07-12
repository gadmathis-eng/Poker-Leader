-- Allow signed-in users to permanently delete their Pot Master account.

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    uid uuid := auth.uid();
begin
    if uid is null then
        raise exception 'Not authenticated';
    end if;

    delete from public.friend_requests
    where from_user_id = uid or to_user_id = uid;

    delete from public.circle_members
    where user_id = uid;

    delete from public.circles
    where owner_user_id = uid;

    delete from auth.users
    where id = uid;
end;
$$;

revoke all on function public.delete_own_account() from public;
grant execute on function public.delete_own_account() to authenticated;
