create policy "circles_delete_owner"
    on public.circles for delete to authenticated
    using (auth.uid() = owner_user_id);

create policy "circle_members_delete_own"
    on public.circle_members for delete to authenticated
    using (auth.uid() = user_id);
