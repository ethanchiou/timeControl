/** Row to spec. Every rule the engine depends on is applied here, once. */

import { asKind, weekdaysFromMask, type Weekday } from '@/core'
import type {
  BlackoutSpec,
  EventGroup,
  EventSpec,
  ExceptionSpec,
  SeriesSpec,
  TermSpec,
  TodoSpec,
} from '@/core'
import type {
  BlackoutRow,
  EventRow,
  ExceptionRow,
  GroupMemberRow,
  GroupRow,
  SeriesRow,
  TermRow,
  TodoRow,
} from './rows'

export function toTermSpec(row: TermRow): TermSpec {
  return { id: row.id, name: row.name, start: row.start_day_key, end: row.end_day_key }
}

export function toSeriesSpec(row: SeriesRow, term: TermSpec): SeriesSpec {
  return {
    id: row.id,
    title: row.title,
    kind: asKind(row.kind),
    term,
    weekdays: weekdaysFromMask(row.weekdays_mask) as Weekday[],
    startMinute: row.start_minute,
    endMinute: row.end_minute,
    intervalWeeks: Math.max(1, row.interval_weeks),
    startWeek: Math.max(1, row.start_week),
    endWeek: row.end_week,
    location: row.location,
    notes: row.notes,
    colorHex: row.color_hex,
  }
}

export function toBlackoutSpec(row: BlackoutRow): BlackoutSpec {
  return {
    id: row.id,
    start: row.start_day_key,
    end: Math.max(row.end_day_key, row.start_day_key),
    kinds: row.kinds.map(asKind),
    reason: row.reason,
  }
}

export function toExceptionSpec(row: ExceptionRow): ExceptionSpec | null {
  if (!row.series_id || row.kind !== 'skipped') return null
  return { id: row.id, seriesId: row.series_id, day: row.day_key, kind: 'skipped' }
}

/**
 * How a group looks on this viewer's calendar: their own override for the group if they set one,
 * otherwise the group's colour. Never the kind colour.
 */
export function resolveGroup(
  group: GroupRow,
  membership: GroupMemberRow | undefined,
): EventGroup {
  return {
    id: group.id,
    name: group.name,
    colorHex: membership?.color_override_hex ?? group.color_hex,
  }
}

export function toEventSpec(
  row: EventRow,
  viewerId: string,
  groupsById: ReadonlyMap<string, EventGroup>,
  displayNames: ReadonlyMap<string, string>,
): EventSpec {
  const group = row.group_id ? (groupsById.get(row.group_id) ?? null) : null
  return {
    id: row.id,
    title: row.title,
    kind: asKind(row.kind),
    start: new Date(row.start_at),
    end: new Date(row.end_at),
    isAllDay: row.is_all_day,
    location: row.location,
    notes: row.notes,
    reminderOffsetsMinutes: row.reminder_offsets_minutes ?? [],
    isRoutine: row.is_routine,
    colorHex: row.color_hex,
    group,
    authorName: group ? (displayNames.get(row.user_id) ?? 'Someone') : null,
    isMine: row.user_id === viewerId,
  }
}

export function toTodoSpec(row: TodoRow): TodoSpec {
  return {
    id: row.id,
    title: row.title,
    notes: row.notes,
    isDone: row.is_done,
    priority: Math.min(4, Math.max(1, row.priority)),
    day: row.day_key,
    week: row.week_key,
    dueDay: row.due_day_key,
    projectId: row.project_id,
    sortOrder: row.sort_order,
  }
}
