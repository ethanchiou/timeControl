/**
 * Value-type mirrors of the stored records. The engine and ring math only ever see these, so they
 * stay pure and testable. Ported from `Specs.swift`, with the group fields the web adds.
 */

import type { DayKey, Weekday } from './dayKey'
import { weekday } from './dayKey'
import { kindColor, type Kind } from './kind'
import { termWeeks, weekCount, weekNumber, type TermWeeks } from './weekMath'

export interface TermSpec {
  id: string
  name: string
  start: DayKey
  end: DayKey
}

export function termSpecWeeks(term: TermSpec): TermWeeks {
  return termWeeks(term.start, term.end)
}

/** Every week the term spans, 1-based. */
export function termWeekCount(term: TermSpec): number {
  return weekCount(termSpecWeeks(term))
}

/** A recurring course or meeting inside a term. */
export interface SeriesSpec {
  id: string
  title: string
  kind: Kind
  term: TermSpec
  /** Monday-first weekday indices. */
  weekdays: Weekday[]
  /** Minutes since local midnight. */
  startMinute: number
  endMinute: number
  /** 1 = weekly, 2 = biweekly. */
  intervalWeeks: number
  /** 1-based, term-relative, inclusive. */
  startWeek: number
  endWeek: number
  location: string
  notes: string
  colorHex: string | null
}

/** Whether this series has an occurrence in term week `w`, ignoring weekday. */
export function seriesOccursInWeek(s: SeriesSpec, w: number): boolean {
  return w >= s.startWeek && w <= s.endWeek && (w - s.startWeek) % s.intervalWeeks === 0
}

/** Whether this series has an occurrence on `day`. */
export function seriesOccursOn(s: SeriesSpec, day: DayKey): boolean {
  if (!s.weekdays.includes(weekday(day))) return false
  const w = weekNumber(termSpecWeeks(s.term), day)
  if (w === null) return false
  return seriesOccursInWeek(s, w)
}

/** The group an event belongs to, resolved for the current viewer. */
export interface EventGroup {
  id: string
  name: string
  /** The viewer's colour override for the group, else the group's own colour. */
  colorHex: string
}

/** A one-off event: interview, exam, appointment, or anything a group is doing together. */
export interface EventSpec {
  id: string
  title: string
  kind: Kind
  start: Date
  end: Date
  isAllDay: boolean
  location: string
  notes: string
  reminderOffsetsMinutes: number[]
  /** A recurring-ish thing added by hand (gym, club). Hidden with courses by the eye filter. */
  isRoutine: boolean
  /** Overrides the kind's colour; null follows the kind. A group's colour wins over both. */
  colorHex: string | null
  group: EventGroup | null
  /** Display name of the author. Only interesting for group events. */
  authorName: string | null
  /** True when the signed-in user wrote this event. */
  isMine: boolean
}

/** Suppresses recurring occurrences of the given kinds (empty = all kinds) over a day range. */
export interface BlackoutSpec {
  id: string
  start: DayKey
  end: DayKey
  kinds: Kind[]
  reason: string
}

export function blackoutSuppresses(b: BlackoutSpec, kind: Kind, day: DayKey): boolean {
  if (day < b.start || day > b.end) return false
  return b.kinds.length === 0 || b.kinds.includes(kind)
}

/** A per-occurrence override of a series. v1 supports only `skipped`. */
export interface ExceptionSpec {
  id: string
  seriesId: string
  day: DayKey
  kind: 'skipped'
}

export interface TodoSpec {
  id: string
  title: string
  notes: string
  isDone: boolean
  /** 1 = urgent ... 4 = low. */
  priority: number
  day: DayKey | null
  /** Monday of the week the todo is bucketed into, when it is not on a specific day. */
  week: DayKey | null
  dueDay: DayKey | null
  projectId: string | null
  sortOrder: number
}

export type OccurrenceSource =
  | { type: 'series'; seriesId: string; day: DayKey }
  | { type: 'event'; eventId: string }

/** One concrete thing on the calendar: a series instance on a given day, or a one-off event. */
export interface Occurrence {
  id: string
  source: OccurrenceSource
  title: string
  kind: Kind
  day: DayKey
  start: Date
  end: Date
  isAllDay: boolean
  location: string
  notes: string
  colorHex: string
  /** The blackout hiding this occurrence, if any. Views never show suppressed occurrences. */
  suppressedBy: string | null
  /** True for every series occurrence and for events marked routine. */
  isRoutine: boolean
  group: EventGroup | null
  authorName: string | null
  isMine: boolean
}

export function occurrenceKey(source: OccurrenceSource): string {
  return source.type === 'series'
    ? `occ-${source.seriesId}-${source.day}`
    : `evt-${source.eventId}`
}

export function occurrenceColor(colorHex: string | null | undefined, kind: Kind): string {
  return colorHex ?? kindColor(kind)
}

export function isSuppressed(o: Occurrence): boolean {
  return o.suppressedBy !== null
}

export function seriesIdOf(o: Occurrence): string | null {
  return o.source.type === 'series' ? o.source.seriesId : null
}

export function eventIdOf(o: Occurrence): string | null {
  return o.source.type === 'event' ? o.source.eventId : null
}
