# TimeControl backend contract

Hosted Supabase project `TimeControl` (ref `vdbsfdaclvnixmhicchv`, us-east-1). Schema lives in
`supabase/migrations/`; auth settings in `supabase/config.toml`. Push with `supabase db push` and
`supabase config push`. Both native app and web client speak to the same tables through the
publishable key with row-level security doing the access control.

## Conventions every client follows

- **Ids are client-generated UUIDs.** Rows are upserted by `id`; the same UUID on two devices is the
  same record.
- **Soft delete only.** Clients never `delete`; they set `deleted_at = now()`. There are no delete
  policies. Other devices pull the tombstone and remove the row locally.
- **`updated_at` is server-stamped** by a trigger on insert and update. Whatever a client sends is
  ignored. Last-writer-wins compares these server clocks.
- **Pull by cursor.** Per table: `select * where updated_at > :cursor order by updated_at`, tombstones
  included; the new cursor is the max `updated_at` seen. Re-pull from a few seconds before the cursor
  to survive commit-order skew; applying a row twice is harmless.
- **Push in dependency order** so foreign keys hold: `terms` → `series` → `blackouts`,
  `occurrence_exceptions`; `projects` → `todos`; `events` last (groups are never pushed by clients).
- **Soft-delete cascades run on the server**: a term tombstone tombstones its series and blackouts,
  a series tombstone tombstones its exceptions, a project tombstone detaches its todos. Every
  cascaded row gets a fresh `updated_at`, so clients pick them up on the next pull. Clients only need
  to tombstone the parent.
- **Day keys** are `int` days since 2000-01-01, Monday-first weeks (see `DayKey.swift`). Week keys
  are the Monday's day key.
- **Kinds** are strings from the app's `Kind` enum: `course tutorial exam interview appointment
  personal other`. Blackout `kinds` is a `text[]`; empty means every kind.
- **Times**: `events.start_at`/`end_at` are `timestamptz`. Series use minutes since local midnight
  (`start_minute`, `end_minute`) and the local calendar resolves the instant.

## Tables

All personal tables: `id uuid pk`, `user_id uuid` (owner), `created_at`, `updated_at`, `deleted_at`.

| table | columns beyond the common set |
|---|---|
| `profiles` | `id` = auth user id, `display_name` (defaults to the email's local part, set by trigger on sign-up) |
| `terms` | `name`, `start_day_key`, `end_day_key`, `is_archived` |
| `series` | `term_id → terms`, `title`, `kind`, `weekdays_mask` (bit 0 = Monday), `start_minute`, `end_minute`, `interval_weeks`, `start_week`, `end_week`, `location`, `notes`, `color_hex?` |
| `blackouts` | `term_id? → terms`, `start_day_key`, `end_day_key`, `kinds text[]`, `reason` |
| `occurrence_exceptions` | `series_id → series`, `day_key`, `kind` (`skipped`) |
| `events` | `group_id? → groups`, `title`, `kind`, `start_at`, `end_at`, `is_all_day`, `location`, `notes`, `reminder_offsets_minutes int[]`, `is_routine`, `color_hex?`. `user_id` is the **author** and is immutable. |
| `projects` | `title`, `summary`, `notes`, `status` (`active paused done`), `priority` 1–4, `target_day_key?`, `color_hex`, `sort_order`, `completed_at?` |
| `todos` | `project_id? → projects`, `title`, `notes`, `priority`, `is_done`, `completed_at?`, `day_key?`, `week_key?`, `due_day_key?`, `sort_order` |
| `groups` | `name`, `color_hex`, `join_code` (8 chars, unique), `created_by`, `deleted_at` |
| `group_members` | pk (`group_id`, `user_id`), `role` (`owner`/`member`), `color_override_hex?`, `joined_at`. `user_id` also references `profiles(id)`, so a roster with names is one query: `group_members?select=*,profiles(display_name)` |

## Access rules (RLS)

- Personal tables: `user_id = auth.uid()` for everything.
- `events`: readable and editable by the author **or any member of `group_id`**. Inserting into a
  group requires membership. Moving an event out of a group (`group_id → null`) is author-only.
- `groups`: members read and update (rename, recolour). Only `created_by` may set `deleted_at`.
  `join_code` and `created_by` are immutable.
- `group_members`: members see the roster; you edit or delete only your own row (colour override,
  leaving).
- `profiles`: yours plus anyone who shares an **active** group with you. A soft-deleted group grants
  nothing, even though its membership rows remain.

## RPCs (call with `rpc`)

| function | args | returns | notes |
|---|---|---|---|
| `create_group` | `p_name text, p_color_hex text` | `groups` row | creates the group and the owner membership; generates the join code |
| `join_group` | `p_code text` | `groups` row | idempotent; case-insensitive, ignores punctuation |
| `leave_group` | `p_group_id uuid` | void | removes your membership |

Errors surface as Postgres exceptions with these messages: `group_limit_reached` (five active groups
per account, enforced by trigger on every membership insert), `invalid_join_code`,
`only_owner_can_delete_group`, `group_name_required`, `not_authenticated`.

## Realtime

All tables are in the `supabase_realtime` publication; Postgres Changes honour RLS, so a client
subscribed to `events` only receives rows it could select. `events`, `groups` and `group_members`
have `replica identity full`.

## Auth

Email + six-digit code: `signInWithOTP(email)` then `verifyOTP(email, token, type: email)`. The
magic-link template carries `{{ .Token }}`; codes expire after 10 minutes. Sign-up is implicit on
first sign-in. OAuth providers can be added in `config.toml` later without schema changes.

## Local development

`supabase start` runs the stack in Docker (Postgres, Auth, Realtime, Mailpit for captured OTP
emails at http://localhost:56324; ports are the 563xx set in `config.toml`). `supabase db reset`
applies the migrations from scratch.
