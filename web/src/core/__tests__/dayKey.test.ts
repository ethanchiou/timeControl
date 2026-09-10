import { describe, expect, it } from 'vitest'
import {
  addingMonths,
  civil,
  dayKey,
  daysInRange,
  isoString,
  maskOf,
  monthDays,
  monthGrid,
  monthLength,
  monthStart,
  weekday,
  weekdaysFromMask,
  weekStart,
  EPOCH,
  type Weekday,
} from '../dayKey'

const SAT: Weekday = 5
const SUN: Weekday = 6
const MON: Weekday = 0
const THU: Weekday = 3
const FRI: Weekday = 4

describe('DayKey', () => {
  it('epoch is Saturday 2000-01-01', () => {
    expect(civil(EPOCH)).toEqual({ year: 2000, month: 1, day: 1 })
    expect(weekday(EPOCH)).toBe(SAT)
  })

  it('round trips civil dates across the epoch', () => {
    const cases: Array<[number, number, number]> = [
      [1999, 12, 31],
      [2000, 2, 29],
      [2024, 2, 29],
      [2026, 9, 7],
      [2100, 3, 1],
      [1970, 1, 1],
    ]
    for (const [y, m, d] of cases) {
      expect(civil(dayKey(y, m, d))).toEqual({ year: y, month: m, day: d })
    }
    expect(dayKey(1999, 12, 31)).toBe(-1)
    expect(dayKey(1970, 1, 1)).toBe(-10957)
  })

  it('round trips every day over a long span', () => {
    for (let k = -12000; k < 15000; k += 1) {
      const c = civil(k)
      expect(dayKey(c.year, c.month, c.day)).toBe(k)
    }
  })

  it('gives Monday-first weekdays and week starts', () => {
    const mon = dayKey(2026, 9, 7)
    expect(weekday(mon)).toBe(MON)
    expect(weekStart(mon)).toBe(mon)
    const thu = dayKey(2026, 9, 10)
    expect(weekday(thu)).toBe(THU)
    expect(weekStart(thu)).toBe(mon)
    const sun = dayKey(2026, 9, 13)
    expect(weekday(sun)).toBe(SUN)
    expect(weekStart(sun)).toBe(mon)
    // Negative keys still land on the right weekday.
    expect(weekday(dayKey(1999, 12, 31))).toBe(FRI)
  })

  it('does arithmetic in whole days', () => {
    const a = dayKey(2026, 9, 7)
    expect(a + 13 - a).toBe(13)
    expect(daysInRange(a, a + 2).map((k) => civil(k).day)).toEqual([7, 8, 9])
    expect(daysInRange(a, a + 13)).toHaveLength(14)
    expect(isoString(a)).toBe('2026-09-07')
  })

  it('packs weekday masks with bit 0 as Monday', () => {
    const set: Weekday[] = [0, 2, 4]
    expect(maskOf(set)).toBe(0b10101)
    expect(weekdaysFromMask(0b10101)).toEqual(set)
  })

  it('finds month start, length and days', () => {
    const mid = dayKey(2026, 9, 17)
    expect(monthStart(mid)).toBe(dayKey(2026, 9, 1))
    expect(monthLength(mid)).toBe(30)
    expect(monthDays(mid)).toEqual([dayKey(2026, 9, 1), dayKey(2026, 9, 30)])

    expect(monthLength(dayKey(2024, 2, 10))).toBe(29)
    expect(monthLength(dayKey(2026, 2, 10))).toBe(28)
    expect(monthLength(dayKey(2100, 2, 10))).toBe(28)
    expect(monthLength(dayKey(2026, 12, 25))).toBe(31)
    expect(monthDays(dayKey(2026, 12, 25))[1]).toBe(dayKey(2026, 12, 31))
  })

  it('covers the month in whole weeks', () => {
    // September 2026 starts on a Tuesday and ends on a Wednesday.
    const [lo, hi] = monthGrid(dayKey(2026, 9, 17))
    expect(lo).toBe(dayKey(2026, 8, 31))
    expect(hi).toBe(dayKey(2026, 10, 4))
    expect(weekday(lo)).toBe(MON)
    expect(weekday(hi)).toBe(SUN)
    expect((hi - lo + 1) % 7).toBe(0)
  })

  it('keeps the month grid whole and tight for six years of months', () => {
    let day = dayKey(2023, 1, 1)
    while (day < dayKey(2029, 1, 1)) {
      const [lo, hi] = monthGrid(day)
      const [first, last] = monthDays(day)
      expect(weekday(lo)).toBe(MON)
      expect(weekday(hi)).toBe(SUN)
      expect((hi - lo + 1) % 7).toBe(0)
      expect(lo <= first && hi >= last).toBe(true)
      // Never a whole blank week of padding at either end.
      expect(first - lo).toBeLessThan(7)
      expect(hi - last).toBeLessThan(7)
      day = addingMonths(day, 1)
    }
  })

  it('clamps addingMonths into the shorter month', () => {
    expect(addingMonths(dayKey(2026, 1, 31), 1)).toBe(dayKey(2026, 2, 28))
    expect(addingMonths(dayKey(2024, 1, 31), 1)).toBe(dayKey(2024, 2, 29))
    expect(addingMonths(dayKey(2026, 3, 31), -1)).toBe(dayKey(2026, 2, 28))
  })

  it('crosses years in both directions and round trips', () => {
    const dec = dayKey(2026, 12, 15)
    expect(addingMonths(dec, 1)).toBe(dayKey(2027, 1, 15))
    expect(addingMonths(dec, 13)).toBe(dayKey(2028, 1, 15))
    const jan = dayKey(2026, 1, 15)
    expect(addingMonths(jan, -1)).toBe(dayKey(2025, 12, 15))
    expect(addingMonths(jan, -13)).toBe(dayKey(2024, 12, 15))
    expect(addingMonths(jan, 0)).toBe(jan)
    for (let n = -40; n <= 40; n += 1) {
      expect(addingMonths(addingMonths(jan, n), -n)).toBe(jan)
    }
  })
})
