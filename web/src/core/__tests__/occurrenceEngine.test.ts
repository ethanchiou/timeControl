import { describe, expect, it } from 'vitest'
import { dayKey, startOfDay, type Weekday } from '../dayKey'
import { kindColor, type Kind } from '../kind'
import {
  hiddenBy,
  nextOccurrence,
  occurrencesIn,
  occurrencesOn,
  visible,
} from '../occurrenceEngine'
import {
  termSpecWeeks,
  type BlackoutSpec,
  type EventSpec,
  type ExceptionSpec,
  type Occurrence,
  type SeriesSpec,
  type TermSpec,
} from '../specs'
import { daysInWeeks, instant } from '../weekMath'

const MON: Weekday = 0
const TUE: Weekday = 1
const WED: Weekday = 2

const d = (m: number, day: number) => dayKey(2026, m, day)

// Fall 2026: Mon Sep 7 to Fri Dec 18, 15 weeks.
const term: TermSpec = { id: 'term-1', name: 'Fall 2026', start: d(9, 7), end: d(12, 18) }

let seq = 0
function course(
  title = 'CS201',
  opts: Partial<Pick<SeriesSpec, 'weekdays' | 'intervalWeeks' | 'startWeek' | 'endWeek' | 'kind'>> = {},
): SeriesSpec {
  seq += 1
  return {
    id: `series-${seq}`,
    title,
    kind: opts.kind ?? 'course',
    term,
    weekdays: opts.weekdays ?? [MON, WED],
    startMinute: 600,
    endMinute: 690,
    intervalWeeks: opts.intervalWeeks ?? 1,
    startWeek: opts.startWeek ?? 1,
    endWeek: opts.endWeek ?? 14,
    location: '',
    notes: '',
    colorHex: null,
  }
}

function event(title: string, kind: Kind, start: Date, end: Date, extra: Partial<EventSpec> = {}): EventSpec {
  seq += 1
  return {
    id: `event-${seq}`,
    title,
    kind,
    start,
    end,
    isAllDay: false,
    location: '',
    notes: '',
    reminderOffsetsMinutes: [],
    isRoutine: false,
    colorHex: null,
    group: null,
    authorName: null,
    isMine: true,
    ...extra,
  }
}

const days = (occ: Occurrence[]) => occ.map((o) => o.day)

describe('OccurrenceEngine', () => {
  it('hits a weekly course on its weekdays inside its week range', () => {
    const cs = course()
    const occ = occurrencesIn(d(9, 7), d(9, 20), { series: [cs] })
    expect(days(occ)).toEqual([d(9, 7), d(9, 9), d(9, 14), d(9, 16)])
    expect(occ[0]!.start.getHours()).toBe(10)
    expect(occ[0]!.end.getMinutes()).toBe(30)
    expect(occ[0]!.id).toBe(`occ-${cs.id}-${d(9, 7)}`)
    // Week 15 (Dec 14 to 18) is past endWeek 14.
    expect(days(occurrencesIn(d(12, 7), d(12, 18), { series: [course()] }))).toEqual([
      d(12, 7),
      d(12, 9),
    ])
  })

  it('takes biweekly parity from startWeek', () => {
    const s = course('Lab', { weekdays: [TUE], intervalWeeks: 2, startWeek: 2 })
    // Weeks 2 and 4 give Sep 15 and Sep 29; weeks 1, 3 and 5 are skipped.
    expect(days(occurrencesIn(d(9, 7), d(10, 11), { series: [s] }))).toEqual([d(9, 15), d(9, 29)])
  })

  it('drops the days before a term that starts mid week', () => {
    const midWeek: TermSpec = { id: 't2', name: 'T', start: d(9, 9), end: d(12, 18) }
    const s: SeriesSpec = { ...course('X'), term: midWeek, weekdays: [MON, WED], startMinute: 540, endMinute: 600 }
    expect(days(occurrencesIn(d(9, 7), d(9, 16), { series: [s] }))).toEqual([
      d(9, 9),
      d(9, 14),
      d(9, 16),
    ])
  })

  it('suppresses only the matching kinds and days', () => {
    const cs = course()
    const exam = course('Midterm review', { weekdays: [MON], kind: 'exam' })
    // "Clear courses for weeks 8 to 9": Oct 26 to Nov 8.
    const [lo, hi] = daysInWeeks(termSpecWeeks(term), 8, 9)
    const b: BlackoutSpec = { id: 'b1', start: lo, end: hi, kinds: ['course'], reason: 'Exams' }
    const occ = occurrencesIn(d(10, 19), d(11, 11), { series: [cs, exam], blackouts: [b] })

    const suppressed = occ.filter((o) => o.suppressedBy !== null)
    const shown = occ.filter((o) => o.suppressedBy === null)
    expect(suppressed.every((o) => o.kind === 'course' && o.suppressedBy === b.id)).toBe(true)
    expect(days(suppressed)).toEqual([d(10, 26), d(10, 28), d(11, 2), d(11, 4)])
    expect(shown.some((o) => o.kind === 'exam' && o.day === d(10, 26))).toBe(true)
    expect(shown.some((o) => o.kind === 'course' && o.day === d(10, 21))).toBe(true)
    expect(shown.some((o) => o.kind === 'course' && o.day === d(11, 9))).toBe(true)

    // Empty kinds means everything recurring.
    const all: BlackoutSpec = { id: 'b2', start: d(10, 26), end: d(10, 26), kinds: [], reason: '' }
    const occAll = occurrencesOn(d(10, 26), { series: [cs, exam], blackouts: [all] })
    expect(occAll).toHaveLength(2)
    expect(occAll.every((o) => o.suppressedBy !== null)).toBe(true)
  })

  it('never blacks out an event', () => {
    const b: BlackoutSpec = { id: 'b3', start: d(9, 7), end: d(9, 7), kinds: [], reason: '' }
    const dentist = event('Dentist', 'appointment', instant(d(9, 7), 480), instant(d(9, 7), 540))
    const occ = occurrencesOn(d(9, 7), { series: [course()], events: [dentist], blackouts: [b] })
    expect(occ.filter((o) => o.source.type === 'event').every((o) => o.suppressedBy === null)).toBe(true)
    expect(occ.find((o) => o.title === 'CS201')!.suppressedBy).toBe(b.id)
  })

  it('removes exactly one occurrence per skipped exception', () => {
    const cs = course()
    const skip: ExceptionSpec = { id: 'x1', seriesId: cs.id, day: d(9, 9), kind: 'skipped' }
    expect(days(occurrencesIn(d(9, 7), d(9, 16), { series: [cs], exceptions: [skip] }))).toEqual([
      d(9, 7),
      d(9, 14),
      d(9, 16),
    ])
    // An exception for another series does nothing.
    const other: ExceptionSpec = { id: 'x2', seriesId: 'someone-else', day: d(9, 7), kind: 'skipped' }
    expect(occurrencesIn(d(9, 7), d(9, 16), { series: [cs], exceptions: [other] })).toHaveLength(4)
  })

  it('merges events into the display order', () => {
    const cs = course()
    const interview = event('Interview', 'interview', instant(d(9, 7), 15 * 60), instant(d(9, 7), 16 * 60))
    const early = event('Dentist', 'appointment', instant(d(9, 7), 8 * 60), instant(d(9, 7), 9 * 60))
    const allDay = event('Add/drop deadline', 'other', startOfDay(d(9, 7)), startOfDay(d(9, 7)), {
      isAllDay: true,
    })
    const outside = event('Later', 'other', instant(d(9, 30), 600), instant(d(9, 30), 660))

    const occ = occurrencesOn(d(9, 7), { series: [cs], events: [interview, early, allDay, outside] })
    expect(occ.map((o) => o.title)).toEqual(['Add/drop deadline', 'Dentist', 'CS201', 'Interview'])
    expect(occ[3]!.id).toBe(`evt-${interview.id}`)
  })

  it('skips suppressed and past occurrences when finding the next one', () => {
    const cs = course()
    const b: BlackoutSpec = { id: 'b4', start: d(9, 7), end: d(9, 7), kinds: ['course'], reason: '' }
    expect(nextOccurrence(instant(d(9, 7), 9 * 60), { series: [cs], blackouts: [b] })!.day).toBe(d(9, 9))
    // Still in progress counts as next.
    expect(nextOccurrence(instant(d(9, 9), 620), { series: [cs] })!.day).toBe(d(9, 9))
    expect(nextOccurrence(instant(d(9, 9), 700), { series: [cs] })!.day).toBe(d(9, 14))
  })
})

describe('routine, colour and group flags', () => {
  const day = d(9, 7)

  it('marks every series occurrence routine and only marked events', () => {
    const cs: SeriesSpec = { ...course('CS201', { weekdays: [MON] }), endMinute: 660 }
    const gym = event('Gym', 'personal', instant(day, 420), instant(day, 480), { isRoutine: true })
    const interview = event('Interview', 'interview', instant(day, 900), instant(day, 960))
    const occ = occurrencesOn(day, { series: [cs], events: [gym, interview] })
    expect(occ.map((o) => `${o.title}:${o.isRoutine}`)).toEqual([
      'Gym:true',
      'CS201:true',
      'Interview:false',
    ])
  })

  it('lets an event colour reach its occurrence and otherwise follows the kind', () => {
    const gala = event('Gala', 'personal', instant(day, 19 * 60), instant(day, 22 * 60), {
      colorHex: '#EC4899',
    })
    const dentist = event('Dentist', 'appointment', instant(day, 8 * 60), instant(day, 9 * 60))
    const occ = occurrencesOn(day, { events: [gala, dentist] })
    expect(occ.find((o) => o.title === 'Gala')!.colorHex).toBe('#EC4899')
    expect(occ.find((o) => o.title === 'Dentist')!.colorHex).toBe(kindColor('appointment'))
  })

  it('paints a group event in the group colour, over the event and kind colours', () => {
    const group = { id: 'g1', name: 'Study group', colorHex: '#10B981' }
    const shared = event('Problem set', 'course', instant(day, 600), instant(day, 660), {
      group,
      colorHex: '#EC4899',
      authorName: 'Priya Raghunathan',
      isMine: false,
    })
    const occ = occurrencesOn(day, { events: [shared] })
    expect(occ[0]!.colorHex).toBe('#10B981')
    expect(occ[0]!.group!.name).toBe('Study group')
    expect(occ[0]!.authorName).toBe('Priya Raghunathan')
  })

  it('filters routine and group items independently', () => {
    const group = { id: 'g1', name: 'Study group', colorHex: '#10B981' }
    const cs = course('CS201', { weekdays: [MON] })
    const shared = event('Problem set', 'course', instant(day, 900), instant(day, 960), { group })
    const interview = event('Interview', 'interview', instant(day, 1000), instant(day, 1040))
    const all = occurrencesOn(day, { series: [cs], events: [shared, interview] })

    expect(visible(all, { hideRoutine: false, hideGroup: false }).map((o) => o.title)).toEqual([
      'CS201',
      'Problem set',
      'Interview',
    ])
    expect(visible(all, { hideRoutine: true, hideGroup: false }).map((o) => o.title)).toEqual([
      'Problem set',
      'Interview',
    ])
    expect(visible(all, { hideRoutine: false, hideGroup: true }).map((o) => o.title)).toEqual([
      'CS201',
      'Interview',
    ])
    expect(visible(all, { hideRoutine: true, hideGroup: true }).map((o) => o.title)).toEqual([
      'Interview',
    ])
    expect(hiddenBy(all, { hideRoutine: true, hideGroup: true })).toHaveLength(2)
  })

  it('never shows a suppressed occurrence, whatever the filter', () => {
    const cs = course('CS201', { weekdays: [MON] })
    const b: BlackoutSpec = { id: 'b5', start: day, end: day, kinds: [], reason: '' }
    const all = occurrencesOn(day, { series: [cs], blackouts: [b] })
    expect(all).toHaveLength(1)
    expect(visible(all, { hideRoutine: false, hideGroup: false })).toHaveLength(0)
  })
})
