import { useMemo, useState } from 'react'
import { TrashIcon } from '@phosphor-icons/react'
import {
  dayKey,
  dayKeyOf,
  instant,
  kindDefaultReminderMinutes,
  kindName,
  KINDS,
  minuteOfDay,
  startOfDay,
  type DayKey,
  type EventSpec,
  type Kind,
} from '@/core'
import { dayToInputValue, inputValueToMinute, minuteToInputValue } from '@/lib/format'
import { friendlyError } from '@/lib/supabase'
import { newId, useStore, type EventDraft } from '@/data/store'
import {
  Button,
  ColorDot,
  ColorSwatchRow,
  ErrorNote,
  Field,
  Select,
  Sheet,
  Switch,
  TextArea,
  TextInput,
} from '@/ui/primitives'

/** The lead times worth one tap. Anything else is a job for the native app. */
const REMINDERS: Array<{ minutes: number; label: string }> = [
  { minutes: 0, label: 'At the time' },
  { minutes: 10, label: '10 min before' },
  { minutes: 30, label: '30 min before' },
  { minutes: 60, label: '1 hour before' },
  { minutes: 1440, label: '1 day before' },
]

function parseDateInput(value: string): DayKey | null {
  const parts = value.split('-').map(Number)
  if (parts.length !== 3 || parts.some((n) => !Number.isFinite(n))) return null
  return dayKey(parts[0]!, parts[1]!, parts[2]!)
}

interface FormState {
  title: string
  kind: Kind
  isAllDay: boolean
  day: DayKey
  startMinute: number
  endMinute: number
  location: string
  notes: string
  isRoutine: boolean
  colorHex: string | null
  groupId: string | null
  reminders: number[]
}

function initialState(event: EventSpec | null, defaultDay: DayKey): FormState {
  if (!event) {
    const kind: Kind = 'personal'
    const reminder = kindDefaultReminderMinutes(kind)
    // A new event lands on the next whole hour, which is almost always what you meant.
    const nowMinute = minuteOfDay(new Date())
    const start = Math.min(23 * 60, Math.ceil(nowMinute / 60) * 60)
    return {
      title: '',
      kind,
      isAllDay: false,
      day: defaultDay,
      startMinute: start,
      endMinute: Math.min(24 * 60 - 1, start + 60),
      location: '',
      notes: '',
      isRoutine: false,
      colorHex: null,
      groupId: null,
      reminders: reminder === null ? [] : [reminder],
    }
  }
  return {
    title: event.title,
    kind: event.kind,
    isAllDay: event.isAllDay,
    day: dayKeyOf(event.start),
    startMinute: minuteOfDay(event.start),
    endMinute: minuteOfDay(event.end),
    location: event.location,
    notes: event.notes,
    isRoutine: event.isRoutine,
    colorHex: event.colorHex,
    groupId: event.group?.id ?? null,
    reminders: event.reminderOffsetsMinutes,
  }
}

export function EventSheet({
  event,
  defaultDay,
  onClose,
}: {
  /** null creates a new event. */
  event: EventSpec | null
  defaultDay: DayKey
  onClose: () => void
}) {
  const { data, saveEvent, deleteEvent } = useStore()
  const [form, setForm] = useState<FormState>(() => initialState(event, defaultDay))
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [confirmingDelete, setConfirmingDelete] = useState(false)

  const patch = (next: Partial<FormState>) => setForm((prev) => ({ ...prev, ...next }))

  const endsBeforeItStarts = !form.isAllDay && form.endMinute < form.startMinute
  const canSave = form.title.trim().length > 0 && !endsBeforeItStarts && !busy

  const draft = useMemo<EventDraft>(() => {
    const startAt = form.isAllDay ? startOfDay(form.day) : instant(form.day, form.startMinute)
    const endAt = form.isAllDay ? startOfDay(form.day) : instant(form.day, form.endMinute)
    return {
      id: event?.id ?? newId(),
      title: form.title.trim(),
      kind: form.kind,
      startAt,
      endAt,
      isAllDay: form.isAllDay,
      location: form.location.trim(),
      notes: form.notes,
      reminderOffsetsMinutes: [...form.reminders].sort((a, b) => a - b),
      isRoutine: form.isRoutine,
      colorHex: form.colorHex,
      groupId: form.groupId,
    }
  }, [event, form])

  async function save() {
    if (!canSave) return
    setBusy(true)
    const { error: failure } = await saveEvent(draft)
    setBusy(false)
    if (failure) setError(friendlyError(failure))
    else onClose()
  }

  async function remove() {
    if (!event) return
    setBusy(true)
    const { error: failure } = await deleteEvent(event.id)
    setBusy(false)
    if (failure) setError(friendlyError(failure))
    else onClose()
  }

  const groupColor =
    form.groupId === null
      ? null
      : (data.groups.find((g) => g.id === form.groupId)?.resolvedColorHex ?? null)

  return (
    <Sheet
      title={event ? 'Edit event' : 'New event'}
      onClose={onClose}
      onSubmit={save}
      footer={
        <>
          {event ? (
            confirmingDelete ? (
              <div className="mr-auto flex items-center gap-2">
                <span className="text-tiny text-muted">Delete this event?</span>
                <Button tone="danger" onClick={remove} disabled={busy}>
                  Delete
                </Button>
                <Button tone="quiet" onClick={() => setConfirmingDelete(false)}>
                  Keep
                </Button>
              </div>
            ) : (
              <Button tone="danger" className="mr-auto" onClick={() => setConfirmingDelete(true)}>
                <TrashIcon size={14} />
                Delete
              </Button>
            )
          ) : null}
          <Button tone="quiet" onClick={onClose}>
            Cancel
          </Button>
          <Button tone="primary" onClick={save} disabled={!canSave}>
            {busy ? 'Saving' : 'Save'}
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-3">
        {error ? <ErrorNote>{error}</ErrorNote> : null}

        <Field label="Title">
          <TextInput
            value={form.title}
            onChange={(e) => patch({ title: e.target.value })}
            placeholder="Linear algebra midterm"
            autoFocus
          />
        </Field>

        <div className="grid grid-cols-2 gap-3">
          <Field label="Kind">
            <Select
              value={form.kind}
              onChange={(e) => {
                const kind = e.target.value as Kind
                patch({ kind })
              }}
            >
              {KINDS.map((k) => (
                <option key={k} value={k}>
                  {kindName(k)}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Date">
            <TextInput
              type="date"
              value={dayToInputValue(form.day)}
              onChange={(e) => {
                const day = parseDateInput(e.target.value)
                if (day !== null) patch({ day })
              }}
            />
          </Field>
        </div>

        <Switch
          checked={form.isAllDay}
          onChange={(isAllDay) => patch({ isAllDay })}
          label="All day"
        />

        {!form.isAllDay ? (
          <div className="grid grid-cols-2 gap-3">
            <Field label="Starts">
              <TextInput
                type="time"
                value={minuteToInputValue(form.startMinute)}
                onChange={(e) => {
                  const startMinute = inputValueToMinute(e.target.value)
                  patch({
                    startMinute,
                    // Keep the length when you drag the start, the way a calendar does.
                    endMinute: Math.max(form.endMinute + (startMinute - form.startMinute), startMinute),
                  })
                }}
              />
            </Field>
            <Field
              label="Ends"
              error={endsBeforeItStarts ? 'The end is before the start.' : null}
            >
              <TextInput
                type="time"
                value={minuteToInputValue(form.endMinute)}
                onChange={(e) => patch({ endMinute: inputValueToMinute(e.target.value) })}
              />
            </Field>
          </div>
        ) : null}

        <Field label="Group" hint="Anyone in the group can edit a group event.">
          <div className="flex flex-wrap gap-1.5">
            <GroupChoice
              selected={form.groupId === null}
              label="No group"
              onClick={() => patch({ groupId: null })}
            />
            {data.groups.map((group) => (
              <GroupChoice
                key={group.id}
                selected={form.groupId === group.id}
                label={group.name}
                color={group.resolvedColorHex}
                onClick={() => patch({ groupId: group.id })}
              />
            ))}
          </div>
        </Field>

        <Field label="Location">
          <TextInput
            value={form.location}
            onChange={(e) => patch({ location: e.target.value })}
            placeholder="Hewlett 200"
          />
        </Field>

        <Field
          label="Colour"
          hint={
            groupColor
              ? 'A group event always shows the group colour on the calendar.'
              : 'Leave it on the kind and the colour follows if you change the kind.'
          }
        >
          <ColorSwatchRow
            value={form.colorHex}
            onChange={(colorHex) => patch({ colorHex })}
            matching={form.kind}
          />
        </Field>

        <Switch
          checked={form.isRoutine}
          onChange={(isRoutine) => patch({ isRoutine })}
          label="Routine, hidden with courses"
        />

        <Field label="Reminders">
          <div className="flex flex-wrap gap-1.5">
            {REMINDERS.map(({ minutes, label }) => {
              const on = form.reminders.includes(minutes)
              return (
                <button
                  key={minutes}
                  type="button"
                  aria-pressed={on}
                  onClick={() =>
                    patch({
                      reminders: on
                        ? form.reminders.filter((m) => m !== minutes)
                        : [...form.reminders, minutes],
                    })
                  }
                  className={`rounded-full border px-2 py-0.5 text-tiny transition-colors duration-150 ${
                    on
                      ? 'border-transparent bg-accent text-[color:var(--accent-ink)]'
                      : 'border-line text-muted hover:border-line-strong hover:text-ink'
                  }`}
                >
                  {label}
                </button>
              )
            })}
          </div>
        </Field>

        <Field label="Notes">
          <TextArea value={form.notes} onChange={(e) => patch({ notes: e.target.value })} />
        </Field>
      </div>
    </Sheet>
  )
}

function GroupChoice({
  selected,
  label,
  color,
  onClick,
}: {
  selected: boolean
  label: string
  color?: string
  onClick: () => void
}) {
  return (
    <button
      type="button"
      aria-pressed={selected}
      onClick={onClick}
      className={`inline-flex items-center gap-1.5 rounded-full border px-2 py-1 text-tiny transition-colors duration-150 ${
        selected
          ? 'border-accent bg-accent text-[color:var(--accent-ink)]'
          : 'border-line text-muted hover:border-line-strong hover:text-ink'
      }`}
    >
      {color ? <ColorDot hex={selected ? 'currentColor' : color} size={7} /> : null}
      {label}
    </button>
  )
}
