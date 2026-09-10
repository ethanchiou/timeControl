/**
 * Expands recurring series and one-off events into concrete occurrences for a range of days.
 * Ported from `OccurrenceEngine.swift`.
 *
 * Pipeline: series, weekday and week filter, drop skipped exceptions, mark blackouts, merge events,
 * sort. Nothing is materialised; call it for whatever window a view needs. Blackouts apply to
 * recurring series only, never to one-off events.
 */

import { dayKeyOf, type DayKey } from './dayKey'
import { instant } from './weekMath'
import {
  blackoutSuppresses,
  occurrenceColor,
  occurrenceKey,
  seriesOccursOn,
  type BlackoutSpec,
  type EventSpec,
  type ExceptionSpec,
  type Occurrence,
  type SeriesSpec,
} from './specs'

export interface EngineInput {
  series?: readonly SeriesSpec[]
  events?: readonly EventSpec[]
  blackouts?: readonly BlackoutSpec[]
  exceptions?: readonly ExceptionSpec[]
}

/** Day, then all-day items first, then start time, then title, then key. Stable across calls. */
export function displayOrder(a: Occurrence, b: Occurrence): number {
  if (a.day !== b.day) return a.day - b.day
  if (a.isAllDay !== b.isAllDay) return a.isAllDay ? -1 : 1
  const at = a.start.getTime()
  const bt = b.start.getTime()
  if (at !== bt) return at - bt
  if (a.title !== b.title) return a.title < b.title ? -1 : 1
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0
}

export function occurrencesIn(from: DayKey, to: DayKey, input: EngineInput): Occurrence[] {
  const series = input.series ?? []
  const events = input.events ?? []
  const blackouts = input.blackouts ?? []
  const exceptions = input.exceptions ?? []

  const skipped = new Set(
    exceptions.filter((e) => e.kind === 'skipped').map((e) => `${e.seriesId}:${e.day}`),
  )

  const result: Occurrence[] = []

  for (let day = from; day <= to; day += 1) {
    for (const s of series) {
      if (!seriesOccursOn(s, day)) continue
      if (skipped.has(`${s.id}:${day}`)) continue
      const blackout = blackouts.find((b) => blackoutSuppresses(b, s.kind, day))
      const source = { type: 'series', seriesId: s.id, day } as const
      result.push({
        id: occurrenceKey(source),
        source,
        title: s.title,
        kind: s.kind,
        day,
        start: instant(day, s.startMinute),
        end: instant(day, s.endMinute),
        isAllDay: false,
        location: s.location,
        notes: s.notes,
        colorHex: occurrenceColor(s.colorHex, s.kind),
        suppressedBy: blackout ? blackout.id : null,
        isRoutine: true,
        group: null,
        authorName: null,
        isMine: true,
      })
    }
  }

  for (const e of events) {
    const day = dayKeyOf(e.start)
    if (day < from || day > to) continue
    const source = { type: 'event', eventId: e.id } as const
    result.push({
      id: occurrenceKey(source),
      source,
      title: e.title,
      kind: e.kind,
      day,
      start: e.start,
      end: e.end,
      isAllDay: e.isAllDay,
      location: e.location,
      notes: e.notes,
      // A group's colour wins over the event's own colour and over the kind.
      colorHex: e.group ? e.group.colorHex : occurrenceColor(e.colorHex, e.kind),
      suppressedBy: null,
      isRoutine: e.isRoutine,
      group: e.group,
      authorName: e.authorName,
      isMine: e.isMine,
    })
  }

  result.sort(displayOrder)
  return result
}

export function occurrencesOn(day: DayKey, input: EngineInput): Occurrence[] {
  return occurrencesIn(day, day, input)
}

/** The first visible timed occurrence that ends after `now`, looking at most `lookaheadDays` ahead. */
export function nextOccurrence(
  now: Date,
  input: EngineInput,
  lookaheadDays = 14,
): Occurrence | null {
  const start = dayKeyOf(now)
  const all = occurrencesIn(start, start + Math.max(0, lookaheadDays), input)
  return (
    all.find((o) => o.suppressedBy === null && !o.isAllDay && o.end.getTime() > now.getTime()) ??
    null
  )
}

/** The two independent flags behind the eye menu. */
export interface EyeFilter {
  hideRoutine: boolean
  hideGroup: boolean
}

/** Occurrences a filter would remove. Suppressed occurrences are never shown at all. */
export function hiddenBy(occurrences: readonly Occurrence[], filter: EyeFilter): Occurrence[] {
  return occurrences.filter(
    (o) => (filter.hideRoutine && o.isRoutine) || (filter.hideGroup && o.group !== null),
  )
}

/** What a view draws: never suppressed, and never filtered out by the eye. */
export function visible(occurrences: readonly Occurrence[], filter: EyeFilter): Occurrence[] {
  return occurrences.filter(
    (o) =>
      o.suppressedBy === null &&
      !(filter.hideRoutine && o.isRoutine) &&
      !(filter.hideGroup && o.group !== null),
  )
}
