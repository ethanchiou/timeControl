-- Profiles were visible to anyone who had ever shared a group with you, including groups the owner
-- has since soft-deleted (membership rows outlive the group). Only *active* shared groups should
-- grant visibility.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (
    id = auth.uid()
    or exists (
      select 1
      from public.group_members mine
      join public.group_members theirs on theirs.group_id = mine.group_id
      join public.groups g on g.id = mine.group_id
      where mine.user_id = auth.uid()
        and theirs.user_id = profiles.id
        and g.deleted_at is null
    )
  );
