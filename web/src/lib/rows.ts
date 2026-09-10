/** The shapes the tables in `supabase/SCHEMA.md` return. Only the columns the web reads. */

export interface ProfileRow {
  id: string
  display_name: string
}

export interface TermRow {
  id: string
  user_id: string
  name: string
  start_day_key: number
  end_day_key: number
  is_archived: boolean
  deleted_at: string | null
}

export interface SeriesRow {
  id: string
  user_id: string
  term_id: string | null
  title: string
  kind: string
  weekdays_mask: number
  start_minute: number
  end_minute: number
  interval_weeks: number
  start_week: number
  end_week: number
  location: string
  notes: string
  color_hex: string | null
  deleted_at: string | null
}

export interface BlackoutRow {
  id: string
  user_id: string
  term_id: string | null
  start_day_key: number
  end_day_key: number
  kinds: string[]
  reason: string
  deleted_at: string | null
}

export interface ExceptionRow {
  id: string
  user_id: string
  series_id: string | null
  day_key: number
  kind: string
  deleted_at: string | null
}

export interface EventRow {
  id: string
  user_id: string
  group_id: string | null
  title: string
  kind: string
  start_at: string
  end_at: string
  is_all_day: boolean
  location: string
  notes: string
  reminder_offsets_minutes: number[]
  is_routine: boolean
  color_hex: string | null
  deleted_at: string | null
}

export interface ProjectRow {
  id: string
  user_id: string
  title: string
  color_hex: string
  status: string
  deleted_at: string | null
}

export interface TodoRow {
  id: string
  user_id: string
  project_id: string | null
  title: string
  notes: string
  priority: number
  is_done: boolean
  completed_at: string | null
  day_key: number | null
  week_key: number | null
  due_day_key: number | null
  sort_order: number
  deleted_at: string | null
}

export interface GroupRow {
  id: string
  name: string
  color_hex: string
  join_code: string
  created_by: string
  deleted_at: string | null
}

export interface GroupMemberRow {
  group_id: string
  user_id: string
  role: 'owner' | 'member'
  color_override_hex: string | null
  joined_at: string
}
