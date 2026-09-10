/** Intl wrappers. One formatter per shape, built once. */

import { civil, startOfDay, type DayKey } from '@/core'

const time = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' })
const weekdayShort = new Intl.DateTimeFormat(undefined, { weekday: 'short' })
const weekdayLong = new Intl.DateTimeFormat(undefined, { weekday: 'long' })
const dayMonth = new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' })
const fullDate = new Intl.DateTimeFormat(undefined, {
  weekday: 'short',
  month: 'short',
  day: 'numeric',
})
const monthYear = new Intl.DateTimeFormat(undefined, { month: 'long', year: 'numeric' })
// Hour only, so the time gutter stays one line: "8 AM" in a 12 hour locale, "08" in a 24 hour one.
const hourOnly = new Intl.DateTimeFormat(undefined, { hour: 'numeric' })

export function timeLabel(date: Date): string {
  return time.format(date)
}

/** "10:30" for a minute past local midnight. */
export function minuteLabel(minute: number): string {
  const d = new Date(2000, 0, 1, Math.trunc(minute / 60), minute % 60)
  return time.format(d)
}

/** The label beside an hour rule. */
export function hourLabel(hour: number): string {
  return hourOnly.format(new Date(2000, 0, 1, hour))
}

export function timeRange(start: Date, end: Date): string {
  return `${time.format(start)} to ${time.format(end)}`
}

/** The compact form used inside a calendar block, where the words would not fit. */
export function timeRangeCompact(start: Date, end: Date): string {
  return `${time.format(start)}-${time.format(end)}`
}

export function weekdayShortLabel(day: DayKey): string {
  return weekdayShort.format(startOfDay(day))
}

export function weekdayLongLabel(day: DayKey): string {
  return weekdayLong.format(startOfDay(day))
}

export function dayMonthLabel(day: DayKey): string {
  return dayMonth.format(startOfDay(day))
}

export function fullDateLabel(day: DayKey): string {
  return fullDate.format(startOfDay(day))
}

export function monthYearLabel(day: DayKey): string {
  return monthYear.format(startOfDay(day))
}

export function dayNumber(day: DayKey): number {
  return civil(day).day
}

/** "in 3 days", "yesterday". Used for due dates only, where the distance is the point. */
export function relativeDayLabel(day: DayKey, from: DayKey): string {
  const diff = day - from
  if (diff === 0) return 'today'
  if (diff === 1) return 'tomorrow'
  if (diff === -1) return 'yesterday'
  if (diff > 0 && diff < 7) return `in ${diff} days`
  if (diff < 0 && diff > -7) return `${-diff} days ago`
  return dayMonthLabel(day)
}

/** The value an `<input type="date">` wants. */
export function dayToInputValue(day: DayKey): string {
  const c = civil(day)
  const pad = (n: number, w: number) => String(n).padStart(w, '0')
  return `${pad(c.year, 4)}-${pad(c.month, 2)}-${pad(c.day, 2)}`
}

/** The value an `<input type="time">` wants, from minutes past local midnight. */
export function minuteToInputValue(minute: number): string {
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${pad(Math.trunc(minute / 60))}:${pad(minute % 60)}`
}

export function inputValueToMinute(value: string): number {
  const [h, m] = value.split(':')
  return (Number(h) || 0) * 60 + (Number(m) || 0)
}
