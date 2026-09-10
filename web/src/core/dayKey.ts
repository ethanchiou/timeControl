/**
 * A calendar day identified by an integer: days since 2000-01-01 (a Saturday).
 *
 * Ported from `DayKey.swift`. A key names a civil date, not an instant, so it is independent of
 * time zone. Conversion uses Howard Hinnant's civil-date algorithms, exactly as the native app does.
 */

export type DayKey = number

/** Days between 1970-01-01 and 2000-01-01. */
const UNIX_EPOCH_OFFSET = 10957

/** 2000-01-01. */
export const EPOCH: DayKey = 0

export interface Civil {
  year: number
  month: number
  day: number
}

/**
 * Integer division that truncates toward zero, matching Swift's `/` on Int.
 * JavaScript's `/` is floating point, so every division in the algorithms below goes through this.
 */
function idiv(a: number, b: number): number {
  return Math.trunc(a / b)
}

export function dayKey(year: number, month: number, day: number): DayKey {
  const y = month <= 2 ? year - 1 : year
  const era = idiv(y >= 0 ? y : y - 399, 400)
  const yoe = y - era * 400
  const mp = (month + 9) % 12
  const doy = idiv(153 * mp + 2, 5) + day - 1
  const doe = yoe * 365 + idiv(yoe, 4) - idiv(yoe, 100) + doy
  const daysSinceUnix = era * 146097 + doe - 719468
  return daysSinceUnix - UNIX_EPOCH_OFFSET
}

export function civil(key: DayKey): Civil {
  const z = key + UNIX_EPOCH_OFFSET + 719468
  const era = idiv(z >= 0 ? z : z - 146096, 146097)
  const doe = z - era * 146097
  const yoe = idiv(doe - idiv(doe, 1460) + idiv(doe, 36524) - idiv(doe, 146096), 365)
  const y = yoe + era * 400
  const doy = doe - (365 * yoe + idiv(yoe, 4) - idiv(yoe, 100))
  const mp = idiv(5 * doy + 2, 153)
  const d = doy - idiv(153 * mp + 2, 5) + 1
  const m = mp < 10 ? mp + 3 : mp - 9
  return { year: m <= 2 ? y + 1 : y, month: m, day: d }
}

/** Monday-first weekday index: 0 = Monday ... 6 = Sunday. These are bit positions in a weekday mask. */
export type Weekday = 0 | 1 | 2 | 3 | 4 | 5 | 6

export const WEEKDAYS: readonly Weekday[] = [0, 1, 2, 3, 4, 5, 6]

const SHORT_NAMES = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'] as const
const LONG_NAMES = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
] as const

export function weekdayShortName(w: Weekday): string {
  return SHORT_NAMES[w]
}

export function weekdayName(w: Weekday): string {
  return LONG_NAMES[w]
}

/** Monday-first weekday of this day. 2000-01-01 (key 0) was a Saturday, index 5. */
export function weekday(key: DayKey): Weekday {
  return (((key % 7) + 7 + 5) % 7) as Weekday
}

/** The Monday that starts this day's week. Week keys are always this value. */
export function weekStart(key: DayKey): DayKey {
  return key - weekday(key)
}

/** The seven days of this day's week, Monday first. */
export function weekDays(key: DayKey): DayKey[] {
  const start = weekStart(key)
  return [0, 1, 2, 3, 4, 5, 6].map((i) => start + i)
}

export function monthStart(key: DayKey): DayKey {
  const c = civil(key)
  return dayKey(c.year, c.month, 1)
}

export function monthLength(key: DayKey): number {
  const c = civil(key)
  const next = c.month === 12 ? dayKey(c.year + 1, 1, 1) : dayKey(c.year, c.month + 1, 1)
  return next - monthStart(key)
}

/** First and last day of this day's month. */
export function monthDays(key: DayKey): [DayKey, DayKey] {
  const start = monthStart(key)
  return [start, start + (monthLength(key) - 1)]
}

/**
 * The whole Monday-started weeks covering this day's month, which is the span a month grid draws.
 * Leading and trailing cells spill into the neighbouring months, so the span is a multiple of seven.
 */
export function monthGrid(key: DayKey): [DayKey, DayKey] {
  const [first, last] = monthDays(key)
  return [weekStart(first), weekStart(last) + 6]
}

/**
 * This day moved by whole months, clamped into the target month: 2026-01-31 plus one month is
 * 2026-02-28, not 2026-03-03.
 */
export function addingMonths(key: DayKey, months: number): DayKey {
  const c = civil(key)
  const total = c.year * 12 + (c.month - 1) + months
  // Floored division so months before year 0 land in the right year.
  const year = total >= 0 ? idiv(total, 12) : idiv(total - 11, 12)
  const month = total - year * 12 + 1
  const length = monthLength(dayKey(year, month, 1))
  return dayKey(year, month, Math.min(c.day, length))
}

/** Every day from `from` to `to`, inclusive. */
export function daysInRange(from: DayKey, to: DayKey): DayKey[] {
  const out: DayKey[] = []
  for (let d = from; d <= to; d += 1) out.push(d)
  return out
}

/** The civil day a `Date` falls on, in the browser's local time zone. */
export function dayKeyOf(date: Date): DayKey {
  return dayKey(date.getFullYear(), date.getMonth() + 1, date.getDate())
}

/** Local midnight starting this day. */
export function startOfDay(key: DayKey): Date {
  const c = civil(key)
  return new Date(c.year, c.month - 1, c.day, 0, 0, 0, 0)
}

export function today(now: Date = new Date()): DayKey {
  return dayKeyOf(now)
}

/** "2026-09-07". Stable, sortable, never localised. */
export function isoString(key: DayKey): string {
  const c = civil(key)
  const pad = (n: number, w: number) => String(n).padStart(w, '0')
  return `${pad(c.year, 4)}-${pad(c.month, 2)}-${pad(c.day, 2)}`
}

export function maskOf(weekdays: Iterable<Weekday>): number {
  let mask = 0
  for (const w of weekdays) mask |= 1 << w
  return mask
}

export function weekdaysFromMask(mask: number): Weekday[] {
  return WEEKDAYS.filter((w) => (mask & (1 << w)) !== 0)
}
