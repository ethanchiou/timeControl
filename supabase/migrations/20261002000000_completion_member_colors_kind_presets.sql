-- Completion, per-member event colours, linked todos and per-user kind colours.
--
-- Everything here is additive: nullable or defaulted columns on existing tables plus one new table.
-- No row is rewritten or removed, and the clients that predate this migration keep working (an
-- upsert only writes the columns in its payload, so the new columns keep their defaults).

-- ---------------------------------------------------------------------------
-- Events: completion
-- ---------------------------------------------------------------------------

-- Each member tracks a group event through their own linked todo (todos are personal). When
-- `shared_completion` is on, one member finishing it finishes it for everyone, and that is recorded
-- here where every member can read it. Off by default: everyone in a group having the same
-- assignment due does not mean one person handing it in finishes it for the rest.
alter table public.events
  add column shared_completion boolean not null default false,
  add column completed_at timestamptz,
  add column completed_by uuid references auth.users (id) on delete set null;

-- ---------------------------------------------------------------------------
-- Todos: the event a todo tracks
-- ---------------------------------------------------------------------------

-- A non-routine event gets a todo per member so it lands in the day's task list and the ring. The
-- todo is personal (ordinary RLS); its id is derived from (event id, user id) on the client so two
-- devices creating it at once produce one row.
alter table public.todos
  add column event_id uuid references public.events (id) on delete set null;

create index todos_event_idx on public.todos (event_id) where event_id is not null;

-- ---------------------------------------------------------------------------
-- Per-member event colour
-- ---------------------------------------------------------------------------

-- How one member wants one group event to look on their own calendar. Private: only the member sees
-- their row. `event_id` is deliberately not a foreign key, so a colour chosen while creating an event
-- can be saved before the event row itself has been pushed.
create table public.event_member_states (
  event_id uuid not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  color_hex text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

create index event_member_states_user_idx on public.event_member_states (user_id);

create trigger event_member_states_set_updated_at
  before insert or update on public.event_member_states
  for each row execute function public.set_updated_at();

alter table public.event_member_states enable row level security;

create policy event_member_states_all on public.event_member_states for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Profiles: colour per kind
-- ---------------------------------------------------------------------------

-- `{ "<kind>": "#RRGGBB" }` for the kinds the user has recoloured; a missing kind uses the app's
-- default colour. Shared across the user's devices and the web through the existing profile policies.
alter table public.profiles
  add column kind_colors jsonb not null default '{}'::jsonb;

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------

alter publication supabase_realtime add table public.event_member_states;
