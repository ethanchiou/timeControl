/** Category of a course or event. Fixed in code, mirroring `Kind.swift`. */

export const KINDS = [
  'course',
  'tutorial',
  'exam',
  'interview',
  'appointment',
  'personal',
  'other',
] as const

export type Kind = (typeof KINDS)[number]

export function isKind(value: string): value is Kind {
  return (KINDS as readonly string[]).includes(value)
}

/** Anything the server hands us that is not a known kind reads as `other`. */
export function asKind(value: string | null | undefined): Kind {
  return value && isKind(value) ? value : 'other'
}

const DISPLAY_NAMES: Record<Kind, string> = {
  course: 'Course',
  tutorial: 'Tutorial',
  exam: 'Exam',
  interview: 'Interview',
  appointment: 'Appointment',
  personal: 'Personal',
  other: 'Other',
}

const PLURAL_NAMES: Record<Kind, string> = {
  course: 'Courses',
  tutorial: 'Tutorials',
  exam: 'Exams',
  interview: 'Interviews',
  appointment: 'Appointments',
  personal: 'Personal',
  other: 'Other',
}

const COLORS: Record<Kind, string> = {
  course: '#4F7CFF',
  tutorial: '#06B6D4',
  exam: '#E5484D',
  interview: '#F59E0B',
  appointment: '#10B981',
  personal: '#A855F7',
  other: '#6B7280',
}

const DEFAULT_REMINDERS: Record<Kind, number | null> = {
  course: 10,
  tutorial: 10,
  exam: 60,
  interview: 60,
  appointment: 30,
  personal: null,
  other: null,
}

export function kindName(kind: Kind): string {
  return DISPLAY_NAMES[kind]
}

export function kindPluralName(kind: Kind): string {
  return PLURAL_NAMES[kind]
}

export function kindColor(kind: Kind): string {
  return COLORS[kind]
}

export function kindDefaultReminderMinutes(kind: Kind): number | null {
  return DEFAULT_REMINDERS[kind]
}
