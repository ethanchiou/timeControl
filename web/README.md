# TimeControl web

The web client for TimeControl. Same backend, same rules, same product as the native SwiftUI app:
recurring courses inside a term, non-destructive blackouts, one-off and group events, day/week/month
calendars, todos with progress rings.

Vite + React 18 + TypeScript + Tailwind + `@supabase/supabase-js`. No server of its own.

## Run it

```sh
cd web
npm install
cp .env.example .env.local     # then fill in the two values, see below
npm run dev                    # http://localhost:5173
```

```sh
npm run build       # tsc --noEmit, then vite build
npm run typecheck
npm test            # engine parity tests, pinned to America/Los_Angeles so the DST cases match Swift
```

## Which backend

`.env.local` holds two values:

```
VITE_SUPABASE_URL=...
VITE_SUPABASE_KEY=...
```

**Hosted** (what this is currently pointed at). The values live outside the repo in
`~/.config/timecontrol/supabase.env` as `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`. Copy those two
across.

**Local stack.** When the Docker stack is running at the repo root, `supabase status -o env` prints
`API_URL` and `ANON_KEY`; use those instead. Local sign-in codes are captured by Mailpit at
http://localhost:54324, so no helper script is needed.

The app never holds a service role key. Only the two dev scripts below read one, at run time, from
outside the repo.

## Signing in during development

The real path is the only path in the UI: type an email, get a six digit code, type the code. A
magic link works too, since `detectSessionInUrl` is on.

The hosted project's default mailer only delivers to the project owner's address. A throwaway test
account will therefore never receive its code by email, and `signInWithOtp` returns an error for it.
The sign-in page is built for that: it shows the error softly and still advances to the code box, so
a code obtained another way can be typed in.

```sh
node dev/otp.mjs tc-test-1@example.com     # prints the six digit code
```

That asks the auth admin API for the same code the email would have carried. It reads
`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` from `~/.config/timecontrol/supabase.env` at run
time, and never prints them.

## Development fixtures

```sh
node dev/seed.mjs                                       # a term, three courses, a blackout, todos
node dev/seed.mjs --email tc-test-2@example.com         # the same, for a second account
node dev/seed.mjs --email tc-test-2@example.com --join ABCD2345 --group-event
```

Fixed UUIDs, so running it twice changes nothing. It writes through the REST API as a real signed-in
user rather than into Postgres directly, which means every row has to pass row-level security exactly
as the app's own writes do. The last form is how the two-account group test is set up: the second
account joins with a join code and adds an event, which should appear in the first account's open
browser without a reload.

There is no `seed.sql`: it would need a local Postgres, and the local stack is not what this is
pointed at.

## Layout

```
src/core        the engine, ported from Packages/TimeControlCore. Pure, no React, no network.
                dayKey, weekMath, kind, specs, occurrenceEngine, ringMath, and parity tests.
src/lib         supabase client, row types, row-to-spec mappers, Intl formatters
src/data        auth, the store (fetch, mutate, realtime), the eye filter's per-scale state
src/ui          primitives, the shell, the calendar bar, occurrence presentation
src/features    the day grid, overlap packing, the event and todo sheets, the schedule hook
src/pages       SignIn, Today, Week, Month, Todos, Groups, Terms
dev             otp.mjs, seed.mjs
```

## Rules worth knowing before changing anything

- **Day keys are integers**, days since 2000-01-01, and weeks start on Monday. Never build a time by
  adding minutes to midnight; `instant(day, minute)` builds the local wall clock, which is what
  survives a DST boundary. The tests in `src/core/__tests__` are ported from the Swift suite and are
  the contract.
- **The engine is pure.** Rows become specs in `src/lib/mappers.ts` before anything computes.
- **Colour.** A series or a personal event uses its own `color_hex`, falling back to the kind colour.
  A group event uses the viewer's `color_override_hex` for that group, falling back to the group's
  colour, and ignores both the event colour and the kind. Group items also carry a people icon and
  the group's name.
- **Blackouts suppress series occurrences only**, never events, and only for the kinds they name
  (empty means every kind). A suppressed occurrence is never drawn.
- **The eye has two independent flags**, hide routine and hide group. A month opens with both on; a
  day and a week open with both off. The button says how many items it is holding back.
- **Writes follow the sync contract**: client-generated UUIDs, upsert by id, soft delete by setting
  `deleted_at`, and every read filters `deleted_at is null`.

## Not here yet

Editing terms, courses and blackouts is read-only on the web; the native app owns it. Projects are
shown as labels on todos but are not editable. Notifications and the calendar mirror are native only.
