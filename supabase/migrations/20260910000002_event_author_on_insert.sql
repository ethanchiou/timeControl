-- Clients upsert rows by id. Postgres evaluates the INSERT policy's WITH CHECK on the proposed row
-- even when ON CONFLICT takes the UPDATE path, so a member re-upserting another member's group
-- event (with that member as user_id) was refused. Stamp the proposed row with the caller on the
-- insert path; on the update path `events_guard_author` restores the original author.
create or replace function public.stamp_event_author()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is not null then
    new.user_id = auth.uid();
  end if;
  return new;
end
$$;

create trigger events_stamp_author
  before insert on public.events
  for each row execute function public.stamp_event_author();
