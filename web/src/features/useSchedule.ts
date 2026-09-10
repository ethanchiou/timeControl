import { useMemo } from 'react'
import {
  hiddenBy,
  occurrencesIn,
  termSpecWeeks,
  visible,
  weekNumber,
  weekCount,
  type DayKey,
  type EyeFilter,
  type Occurrence,
  type TermSpec,
} from '@/core'
import { useStore } from '@/data/store'

export interface Schedule {
  /** Everything the engine produced, suppressed items included. */
  all: Occurrence[]
  /** What the view draws. */
  shown: Occurrence[]
  /** How many the eye is holding back. Suppressed items are not counted; they are never shown. */
  hiddenCount: number
  byDay: Map<DayKey, Occurrence[]>
}

export function useSchedule(from: DayKey, to: DayKey, filter: EyeFilter): Schedule {
  const { data } = useStore()
  return useMemo(() => {
    const all = occurrencesIn(from, to, {
      series: data.series,
      events: data.events,
      blackouts: data.blackouts,
      exceptions: data.exceptions,
    })
    const shown = visible(all, filter)
    const notSuppressed = all.filter((o) => o.suppressedBy === null)
    const byDay = new Map<DayKey, Occurrence[]>()
    for (const o of shown) {
      const bucket = byDay.get(o.day)
      if (bucket) bucket.push(o)
      else byDay.set(o.day, [o])
    }
    return { all, shown, hiddenCount: hiddenBy(notSuppressed, filter).length, byDay }
  }, [from, to, filter, data.series, data.events, data.blackouts, data.exceptions])
}

/** The term a day falls in, and where in it that day sits. */
export function useTermContext(day: DayKey): {
  term: TermSpec | null
  week: number | null
  weeks: number
} {
  const { data } = useStore()
  return useMemo(() => {
    const term = data.terms.find((t) => day >= t.start && day <= t.end) ?? null
    if (!term) return { term: null, week: null, weeks: 0 }
    const weeks = termSpecWeeks(term)
    return { term, week: weekNumber(weeks, day), weeks: weekCount(weeks) }
  }, [data.terms, day])
}
