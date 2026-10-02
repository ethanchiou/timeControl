/** Category of a course or event. Fixed in code, mirroring `Kind.swift`. */

export const KINDS = [
  'course',
  'tutorial',
  'assignment',
  'exam',
  'interview',
  'appointment',
  'hangout',
  'personal',
  'other',
] as const

export type Kind = (typeof KINDS)[number]

export function isKind(value: string): value is Kind {
  return (KINDS as readonly string[]).includes(value)
}

/**
 * Anything the server hands us that is not a known kind reads as `other`. Only for display: a row
 * written back must carry the kind string it arrived with, or a newer client's tag is lost.
 */
export function asKind(value: string | null | undefined): Kind {
  return value && isKind(value) ? value : 'other'
}

const DISPLAY_NAMES: Record<Kind, string> = {
  course: 'Course',
  tutorial: 'Tutorial',
  assignment: 'Assignment',
  exam: 'Exam',
  interview: 'Interview',
  appointment: 'Appointment',
  hangout: 'Hangout',
  personal: 'Personal',
  other: 'Other',
}

const PLURAL_NAMES: Record<Kind, string> = {
  course: 'Courses',
  tutorial: 'Tutorials',
  assignment: 'Assignments',
  exam: 'Exams',
  interview: 'Interviews',
  appointment: 'Appointments',
  hangout: 'Hangouts',
  personal: 'Personal',
  other: 'Other',
}

const COLORS: Record<Kind, string> = {
  course: '#4F7CFF',
  tutorial: '#06B6D4',
  assignment: '#F97316',
  exam: '#E5484D',
  interview: '#F59E0B',
  appointment: '#10B981',
  hangout: '#EC4899',
  personal: '#A855F7',
  other: '#6B7280',
}

const DEFAULT_REMINDERS: Record<Kind, number | null> = {
  course: 10,
  tutorial: 10,
  assignment: 1440,
  exam: 60,
  interview: 60,
  appointment: 30,
  hangout: 30,
  personal: null,
  other: null,
}

/**
 * The viewer's own colour per kind, from `profiles.kind_colors`. Module state rather than a React
 * context so the pure engine and every badge read one answer; the store sets it before it publishes
 * a snapshot, and everything that paints re-renders with that snapshot.
 */
let overrides: Partial<Record<Kind, string>> = {}

export function setKindColorOverrides(map: Record<string, string> | null | undefined): void {
  const next: Partial<Record<Kind, string>> = {}
  for (const [key, hex] of Object.entries(map ?? {})) {
    if (isKind(key) && typeof hex === 'string') next[key] = hex
  }
  overrides = next
}

export function kindColorOverrides(): Partial<Record<Kind, string>> {
  return { ...overrides }
}

export function kindName(kind: Kind): string {
  return DISPLAY_NAMES[kind]
}

export function kindPluralName(kind: Kind): string {
  return PLURAL_NAMES[kind]
}

/** What `kind` paints with: the viewer's colour for it, else the default. */
export function kindColor(kind: Kind): string {
  return overrides[kind] ?? COLORS[kind]
}

/** The default, whatever the viewer chose. */
export function kindDefaultColor(kind: Kind): string {
  return COLORS[kind]
}

export function kindDefaultReminderMinutes(kind: Kind): number | null {
  return DEFAULT_REMINDERS[kind]
}
