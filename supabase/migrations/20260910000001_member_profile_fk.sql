-- Let clients join a roster to display names in one query:
--   group_members?select=*,profiles(display_name)
-- profiles.id is created by trigger the moment the auth user exists, so the FK always resolves.
alter table public.group_members
  add constraint group_members_user_id_profiles_fkey
  foreign key (user_id) references public.profiles (id) on delete cascade;
