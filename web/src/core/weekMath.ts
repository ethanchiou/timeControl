/**
 * Week numbering for a term, and the DST-safe day/minute to instant conversion.
 * Ported from `WeekMath.swift`.
 */

import { civil, weekStart, type DayKey } from './dayKey'

/** Week 1 starts on the Monday of the week containing `termStart`. */
export interface TermWeeks {
  readonly termStart: DayKey
  readonly termEnd: DayKey
}

export function termWeeks(termStart: DayKey, termEnd: DayKey): TermWeeks {
  return { termStart, termEnd: Math.max(termEnd, termStart) }
}

/** Monday of week 1. */
export function firstWeekStart(t: TermWeeks): DayKey {
  return weekStart(t.termStart)
}

/** Number of (possibly partial) weeks the term spans. */
export function weekCount(t: TermWeeks): number {
  return Math.trunc((t.termEnd - firstWeekStart(t)) / 7) + 1
}

/** 1-based week number of `day`, or null when `day` falls outside the term. */
export function weekNumber(t: TermWeeks, day: DayKey): number | null {
  if (day < t.termStart || day > t.termEnd) return null
  return Math.trunc((day - firstWeekStart(t)) / 7) + 1
}

/** Monday of week `n` (1-based). Not clamped to the term. */
export function weekStartOfWeek(t: TermWeeks, n: number): DayKey {
  return firstWeekStart(t) + 7 * (n - 1)
}

/** The seven days of week `n`, not clamped to the term. */
export function daysInWeek(t: TermWeeks, n: number): [DayKey, DayKey] {
  const start = weekStartOfWeek(t, n)
  return [start, start + 6]
}

/** The days of weeks `first` through `last`, clamped to the term. Backs "clear weeks 8-9". */
export function daysInWeeks(t: TermWeeks, first: number, last: number): [DayKey, DayKey] {
  const lo = Math.max(weekStartOfWeek(t, first), t.termStart)
  const hi = Math.min(weekStartOfWeek(t, last) + 6, t.termEnd)
  return [lo, Math.max(lo, hi)]
}

/**
 * The instant at `minute` minutes past local midnight on `day`.
 *
 * DST-safe: it builds the local wall-clock time rather than adding seconds to midnight, so 10:00 on
 * a spring-forward day is 10:00 and not 11:00.
 */
export function instant(day: DayKey, minute: number): Date {
  const c = civil(day)
  return new Date(c.year, c.month - 1, c.day, Math.trunc(minute / 60), minute % 60, 0, 0)
}

/** Minutes since local midnight of `date`'s day. */
export function minuteOfDay(date: Date): number {
  return date.getHours() * 60 + date.getMinutes()
}
