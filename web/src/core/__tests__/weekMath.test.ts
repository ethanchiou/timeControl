import { describe, expect, it } from 'vitest'
import { dayKey, startOfDay } from '../dayKey'
import {
  daysInWeek,
  daysInWeeks,
  firstWeekStart,
  instant,
  minuteOfDay,
  termWeeks,
  weekCount,
  weekNumber,
} from '../weekMath'

// The whole suite runs under TZ=America/Los_Angeles so the DST assertions match `WeekMathTests.swift`.

describe('TermWeeks', () => {
  // Wed 2026-09-09 to Fri 2026-12-18.
  const t = termWeeks(dayKey(2026, 9, 9), dayKey(2026, 12, 18))

  it('numbers a term starting mid week from its Monday', () => {
    expect(firstWeekStart(t)).toBe(dayKey(2026, 9, 7))
    expect(weekCount(t)).toBe(15)
    expect(weekNumber(t, dayKey(2026, 9, 7))).toBeNull() // before term start
    expect(weekNumber(t, dayKey(2026, 9, 9))).toBe(1)
    expect(weekNumber(t, dayKey(2026, 9, 13))).toBe(1)
    expect(weekNumber(t, dayKey(2026, 9, 14))).toBe(2)
    expect(weekNumber(t, dayKey(2026, 12, 18))).toBe(15)
    expect(weekNumber(t, dayKey(2026, 12, 19))).toBeNull() // after term end
  })

  it('clamps week ranges to the term', () => {
    expect(daysInWeek(t, 1)).toEqual([dayKey(2026, 9, 7), dayKey(2026, 9, 13)])
    expect(daysInWeeks(t, 1, 1)).toEqual([dayKey(2026, 9, 9), dayKey(2026, 9, 13)])
    expect(daysInWeeks(t, 8, 9)).toEqual([dayKey(2026, 10, 26), dayKey(2026, 11, 8)])
    expect(daysInWeeks(t, 15, 15)[1]).toBe(dayKey(2026, 12, 18))
  })
})

describe('instant', () => {
  it('stays on the wall clock across a spring-forward day', () => {
    // 2026-03-08 is the spring-forward day in Los Angeles; midnight + 600 minutes would give 11:00.
    const spring = dayKey(2026, 3, 8)
    const at10 = instant(spring, 600)
    expect(at10.getHours()).toBe(10)
    expect(at10.getMinutes()).toBe(0)
    expect(minuteOfDay(at10)).toBe(600)
    expect(at10.getTime() - startOfDay(spring).getTime()).toBe(9 * 3600 * 1000)
  })

  it('stays on the wall clock across a fall-back day', () => {
    const fall = dayKey(2026, 11, 1)
    const at1030 = instant(fall, 630)
    expect(at1030.getHours()).toBe(10)
    expect(at1030.getMinutes()).toBe(30)
    expect(at1030.getTime() - startOfDay(fall).getTime()).toBe(11.5 * 3600 * 1000)
  })
})
