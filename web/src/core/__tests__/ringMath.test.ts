import { describe, expect, it } from 'vitest'
import { dayKey } from '../dayKey'
import {
  dailyProgress,
  EMPTY_PROGRESS,
  fraction,
  isComplete,
  isEmptyProgress,
  listOrder,
  progressOf,
  projectProgress,
  remaining,
  ringProgress,
  weeklyProgress,
} from '../ringMath'
import type { TodoSpec } from '../specs'

const d = (m: number, day: number) => dayKey(2026, m, day)

let seq = 0
function todo(partial: Partial<TodoSpec> = {}): TodoSpec {
  seq += 1
  return {
    id: `todo-${seq}`,
    title: '',
    notes: '',
    isDone: false,
    priority: 3,
    day: null,
    week: null,
    dueDay: null,
    projectId: null,
    sortOrder: 0,
    ...partial,
  }
}

describe('RingMath', () => {
  it('gives empty progress for an empty set', () => {
    const p = progressOf([])
    expect(p).toEqual(EMPTY_PROGRESS)
    expect(isEmptyProgress(p)).toBe(true)
    expect(fraction(p)).toBe(0)
  })

  it('counts only the exact day', () => {
    const mon = d(9, 7)
    const p = dailyProgress(
      [
        todo({ isDone: true, day: mon }),
        todo({ day: mon }),
        todo({ day: d(9, 8) }),
        todo({ week: mon }),
      ],
      mon,
    )
    expect(p).toEqual({ done: 1, total: 2 })
  })

  it('counts the week bucket and the day bucket but ignores adjacent weeks', () => {
    // Week of Mon Sep 7 to Sun Sep 13.
    const monday = d(9, 7)
    const p = weeklyProgress(
      [
        todo({ isDone: true, week: monday }), // week bucketed, in week
        todo({ day: d(9, 9) }), // day bucketed, in week
        todo({ isDone: true, day: d(9, 13) }), // last day of the week
        todo({ day: d(9, 14) }), // next week's Monday, excluded
        todo({ week: d(9, 14) }), // next week's bucket, excluded
        todo({ day: d(9, 6) }), // previous week's Sunday, excluded
      ],
      monday,
    )
    expect(p).toEqual({ done: 2, total: 3 })
  })

  it('normalises the given day to its Monday', () => {
    const p = weeklyProgress([todo({ week: d(9, 7) }), todo({ day: d(9, 12) })], d(9, 10))
    expect(p.total).toBe(2)
  })

  it('filters by project', () => {
    const p = projectProgress(
      [
        todo({ isDone: true, projectId: 'a' }),
        todo({ projectId: 'a' }),
        todo({ projectId: 'b' }),
        todo({}),
      ],
      'a',
    )
    expect(p).toEqual({ done: 1, total: 2 })
  })

  it('reports fraction, completeness and remainder', () => {
    expect(fraction(ringProgress(0, 0))).toBe(0)
    expect(isEmptyProgress(ringProgress(0, 0))).toBe(true)
    expect(isComplete(ringProgress(0, 0))).toBe(false)

    const half = ringProgress(1, 2)
    expect(fraction(half)).toBe(0.5)
    expect(isComplete(half)).toBe(false)
    expect(remaining(half)).toBe(1)

    const full = ringProgress(3, 3)
    expect(isComplete(full)).toBe(true)
    expect(remaining(full)).toBe(0)
  })

  it('clamps done within bounds', () => {
    expect(ringProgress(5, 3).done).toBe(3)
    expect(ringProgress(-1, 3).done).toBe(0)
    expect(ringProgress(2, -4)).toEqual({ done: 0, total: 0 })
  })

  it('puts open before done, then orders by priority', () => {
    const openLow = todo({ priority: 4 })
    const openHigh = todo({ priority: 1 })
    const doneHigh = todo({ isDone: true, priority: 1 })
    expect(listOrder(openHigh, openLow)).toBeLessThan(0)
    expect(listOrder(openLow, openHigh)).toBeGreaterThan(0)
    expect(listOrder(openLow, doneHigh)).toBeLessThan(0)
    expect(listOrder(doneHigh, openLow)).toBeGreaterThan(0)
  })
})
