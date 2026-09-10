-- TimeControl schema v1: personal data sync + shared groups.
--
-- Every user-owned table carries `user_id`, server-stamped `updated_at`, and a soft-delete
-- `deleted_at`. Clients never hard-delete: they set `deleted_at`, and other devices pull the
-- tombstone. Pull = `where updated_at > cursor`, tombstones included.
--
-- Day keys are days since 2000-01-01 (see DayKey.swift). Kinds are the app's `Kind` enum raw values.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  -- Server-authoritative: the client's value is ignored, so last-writer-wins compares server clocks.
  new.updated_at = now();
  return new;
end
$$;

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), split_part(coalesce(new.email, ''), '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Groups
-- ---------------------------------------------------------------------------

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  color_hex text not null default '#4F7CFF',
  join_code text not null unique,
  created_by uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  -- How this member wants the group to look on their own calendar; null follows the group colour.
  color_override_hex text,
  joined_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index group_members_user_idx on public.group_members (user_id);

create trigger groups_set_updated_at
  before update on public.groups
  for each row execute function public.set_updated_at();

create trigger group_members_set_updated_at
  before update on public.group_members
  for each row execute function public.set_updated_at();

-- Membership check that bypasses RLS so policies on group_members itself do not recurse.
create or replace function public.is_group_member(gid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.group_members
    where group_id = gid and user_id = auth.uid()
  );
$$;

create or replace function public.active_group_count(uid uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
  from public.group_members gm
  join public.groups g on g.id = gm.group_id
  where gm.user_id = uid and g.deleted_at is null;
$$;

-- Five groups per account. Enforced here so every path (RPC or direct insert) hits it.
create or replace function public.enforce_group_cap()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.active_group_count(new.user_id) >= 5 then
    raise exception 'group_limit_reached' using errcode = 'P0001';
  end if;
  return new;
end
$$;

create trigger group_members_enforce_cap
  before insert on public.group_members
  for each row execute function public.enforce_group_cap();

-- Only the creator may delete (soft-delete) a group; members leave instead.
create or replace function public.guard_group_delete()
returns trigger
language plpgsql
as $$
begin
  if new.deleted_at is distinct from old.deleted_at and auth.uid() is distinct from old.created_by then
    raise exception 'only_owner_can_delete_group' using errcode = 'P0001';
  end if;
  new.created_by = old.created_by;
  new.join_code = old.join_code;
  return new;
end
$$;

create trigger groups_guard_delete
  before update on public.groups
  for each row execute function public.guard_group_delete();

-- Unambiguous alphabet, eight characters: no 0/O, 1/I.
create or replace function public.generate_join_code()
returns text
language plpgsql
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code text := '';
  i int;
begin
  for i in 1..8 loop
    code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
  end loop;
  return code;
end
$$;

create or replace function public.create_group(p_name text, p_color_hex text default '#4F7CFF')
returns public.groups
language plpgsql
security definer
set search_path = public
as $$
declare
  g public.groups;
  code text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if length(trim(p_name)) = 0 then
    raise exception 'group_name_required' using errcode = 'P0001';
  end if;
  if public.active_group_count(auth.uid()) >= 5 then
    raise exception 'group_limit_reached' using errcode = 'P0001';
  end if;
  loop
    code := public.generate_join_code();
    exit when not exists (select 1 from public.groups where join_code = code);
  end loop;
  insert into public.groups (name, color_hex, join_code, created_by)
  values (trim(p_name), coalesce(p_color_hex, '#4F7CFF'), code, auth.uid())
  returning * into g;
  insert into public.group_members (group_id, user_id, role)
  values (g.id, auth.uid(), 'owner');
  return g;
end
$$;

create or replace function public.join_group(p_code text)
returns public.groups
language plpgsql
security definer
set search_path = public
as $$
declare
  g public.groups;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select * into g from public.groups
  where join_code = upper(regexp_replace(p_code, '[^A-Za-z0-9]', '', 'g')) and deleted_at is null;
  if not found then
    raise exception 'invalid_join_code' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.group_members where group_id = g.id and user_id = auth.uid()) then
    return g;
  end if;
  insert into public.group_members (group_id, user_id, role)
  values (g.id, auth.uid(), 'member');
  return g;
end
$$;

create or replace function public.leave_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.group_members where group_id = p_group_id and user_id = auth.uid();
end
$$;

-- ---------------------------------------------------------------------------
-- Personal data
-- ---------------------------------------------------------------------------

create table public.terms (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null default '',
  start_day_key int not null default 0,
  end_day_key int not null default 0,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.series (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  term_id uuid references public.terms (id) on delete cascade,
  title text not null default '',
  kind text not null default 'course',
  weekdays_mask int not null default 0,
  start_minute int not null default 540,
  end_minute int not null default 600,
  interval_weeks int not null default 1,
  start_week int not null default 1,
  end_week int not null default 1,
  location text not null default '',
  notes text not null default '',
  color_hex text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.blackouts (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  term_id uuid references public.terms (id) on delete set null,
  start_day_key int not null default 0,
  end_day_key int not null default 0,
  kinds text[] not null default '{}',
  reason text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.occurrence_exceptions (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  series_id uuid references public.series (id) on delete cascade,
  day_key int not null default 0,
  kind text not null default 'skipped',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.events (
  id uuid primary key,
  -- The author. For a group event this is whoever created it; any member may edit it.
  user_id uuid not null references auth.users (id) on delete cascade,
  group_id uuid references public.groups (id) on delete cascade,
  title text not null default '',
  kind text not null default 'other',
  start_at timestamptz not null,
  end_at timestamptz not null,
  is_all_day boolean not null default false,
  location text not null default '',
  notes text not null default '',
  reminder_offsets_minutes int[] not null default '{}',
  is_routine boolean not null default false,
  color_hex text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.projects (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null default '',
  summary text not null default '',
  notes text not null default '',
  status text not null default 'active',
  priority int not null default 3,
  target_day_key int,
  color_hex text not null default '#4F7CFF',
  sort_order int not null default 0,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.todos (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  project_id uuid references public.projects (id) on delete set null,
  title text not null default '',
  notes text not null default '',
  priority int not null default 3,
  is_done boolean not null default false,
  completed_at timestamptz,
  day_key int,
  week_key int,
  due_day_key int,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index terms_user_updated_idx on public.terms (user_id, updated_at);
create index series_user_updated_idx on public.series (user_id, updated_at);
create index blackouts_user_updated_idx on public.blackouts (user_id, updated_at);
create index occurrence_exceptions_user_updated_idx on public.occurrence_exceptions (user_id, updated_at);
create index events_user_updated_idx on public.events (user_id, updated_at);
create index events_group_updated_idx on public.events (group_id, updated_at) where group_id is not null;
create index projects_user_updated_idx on public.projects (user_id, updated_at);
create index todos_user_updated_idx on public.todos (user_id, updated_at);

create trigger terms_set_updated_at before insert or update on public.terms for each row execute function public.set_updated_at();
create trigger series_set_updated_at before insert or update on public.series for each row execute function public.set_updated_at();
create trigger blackouts_set_updated_at before insert or update on public.blackouts for each row execute function public.set_updated_at();
create trigger occurrence_exceptions_set_updated_at before insert or update on public.occurrence_exceptions for each row execute function public.set_updated_at();
create trigger events_set_updated_at before insert or update on public.events for each row execute function public.set_updated_at();
create trigger projects_set_updated_at before insert or update on public.projects for each row execute function public.set_updated_at();
create trigger todos_set_updated_at before insert or update on public.todos for each row execute function public.set_updated_at();

-- Soft-delete cascades, mirroring the app's SwiftData delete rules: term → series + blackouts,
-- series → exceptions, project → todos lose their project. Bumping updated_at (via the trigger)
-- makes every device pull the change.
create or replace function public.cascade_term_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    update public.series set deleted_at = new.deleted_at where term_id = new.id and deleted_at is null;
    update public.blackouts set deleted_at = new.deleted_at where term_id = new.id and deleted_at is null;
  end if;
  return new;
end
$$;

create or replace function public.cascade_series_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    update public.occurrence_exceptions set deleted_at = new.deleted_at where series_id = new.id and deleted_at is null;
  end if;
  return new;
end
$$;

create or replace function public.cascade_project_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    update public.todos set project_id = null where project_id = new.id and deleted_at is null;
  end if;
  return new;
end
$$;

create trigger terms_cascade_delete after update on public.terms for each row execute function public.cascade_term_delete();
create trigger series_cascade_delete after update on public.series for each row execute function public.cascade_series_delete();
create trigger projects_cascade_delete after update on public.projects for each row execute function public.cascade_project_delete();

-- The author of an event never changes, whoever edits it.
create or replace function public.guard_event_author()
returns trigger
language plpgsql
as $$
begin
  new.user_id = old.user_id;
  return new;
end
$$;

create trigger events_guard_author before update on public.events for each row execute function public.guard_event_author();

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.terms enable row level security;
alter table public.series enable row level security;
alter table public.blackouts enable row level security;
alter table public.occurrence_exceptions enable row level security;
alter table public.events enable row level security;
alter table public.projects enable row level security;
alter table public.todos enable row level security;

-- Profiles: yours, plus anyone you share a group with (to show authors and member lists).
create policy profiles_select on public.profiles for select to authenticated
  using (
    id = auth.uid()
    or exists (
      select 1 from public.group_members mine
      join public.group_members theirs on theirs.group_id = mine.group_id
      where mine.user_id = auth.uid() and theirs.user_id = profiles.id
    )
  );
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- Groups: members read and edit; creation and joining go through the RPCs.
create policy groups_select on public.groups for select to authenticated
  using (public.is_group_member(id));
create policy groups_update on public.groups for update to authenticated
  using (public.is_group_member(id)) with check (public.is_group_member(id));

-- Members: see the roster of your groups; edit and remove only your own row.
create policy group_members_select on public.group_members for select to authenticated
  using (public.is_group_member(group_id));
create policy group_members_update on public.group_members for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy group_members_delete on public.group_members for delete to authenticated
  using (user_id = auth.uid());

-- Personal tables: your rows only.
create policy terms_all on public.terms for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy series_all on public.series for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy blackouts_all on public.blackouts for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy occurrence_exceptions_all on public.occurrence_exceptions for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy projects_all on public.projects for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy todos_all on public.todos for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Events: your own, plus every event in a group you belong to. Any member edits a group event;
-- only the author can take an event out of a group (a null group_id needs user_id = you).
create policy events_select on public.events for select to authenticated
  using (user_id = auth.uid() or (group_id is not null and public.is_group_member(group_id)));
create policy events_insert on public.events for insert to authenticated
  with check (user_id = auth.uid() and (group_id is null or public.is_group_member(group_id)));
create policy events_update on public.events for update to authenticated
  using (user_id = auth.uid() or (group_id is not null and public.is_group_member(group_id)))
  with check ((group_id is null and user_id = auth.uid()) or (group_id is not null and public.is_group_member(group_id)));

-- No delete policies anywhere: clients soft-delete by updating deleted_at.

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------

alter publication supabase_realtime add table
  public.groups, public.group_members, public.profiles,
  public.terms, public.series, public.blackouts, public.occurrence_exceptions,
  public.events, public.projects, public.todos;

-- Send full old rows so RLS-filtered change events carry enough to act on.
alter table public.events replica identity full;
alter table public.groups replica identity full;
alter table public.group_members replica identity full;
