import { describe, expect, it } from 'vitest'
import { dayKey, startOfDay } from '../dayKey'
import { linkedTodoId, planLinkedTodos, uuid5 } from '../../lib/linkedTodos'
import type { EventRow, TodoRow } from '../../lib/rows'

const today = dayKey(2026, 10, 2)
const user = '11111111-1111-4111-8111-111111111111'
const other = '22222222-2222-4222-8222-222222222222'

let seq = 0
function event(
  title: string,
  dayOffset: number,
  extra: Partial<EventRow> = {},
): EventRow {
  seq += 1
  const start = startOfDay(today + dayOffset)
  return {
    id: `0000000${seq}-0000-4000-8000-000000000000`.slice(-36),
    user_id: user,
    group_id: null,
    title,
    kind: 'assignment',
    start_at: new Date(start.getTime() + 10 * 3_600_000).toISOString(),
    end_at: new Date(start.getTime() + 11 * 3_600_000).toISOString(),
    is_all_day: false,
    location: '',
    notes: '',
    reminder_offsets_minutes: [],
    is_routine: false,
    color_hex: null,
    shared_completion: false,
    completed_at: null,
    completed_by: null,
    deleted_at: null,
    ...extra,
  }
}

function todo(eventId: string | null, extra: Partial<TodoRow> = {}): TodoRow {
  seq += 1
  return {
    id: `todo-${seq}`,
    user_id: user,
    project_id: null,
    title: 'x',
    notes: '',
    priority: 3,
    is_done: false,
    completed_at: null,
    day_key: today + 1,
    week_key: null,
    due_day_key: today + 1,
    sort_order: 0,
    event_id: eventId,
    created_at: '2026-10-01T00:00:00Z',
    deleted_at: null,
    ...extra,
  }
}

describe('uuid5', () => {
  it('matches the RFC 4122 test vector', async () => {
    const dns = '6ba7b810-9dad-11d1-80b4-00c04fd430c8'
    expect(await uuid5(dns, 'www.example.com')).toBe('2ed6657d-e927-568b-95e1-2665a8aea6a2')
  })

  it('derives one todo id per event and user', async () => {
    const e = '33333333-3333-4333-8333-333333333333'
    expect(await linkedTodoId(e, user)).toBe(await linkedTodoId(e.toUpperCase(), user))
    expect(await linkedTodoId(e, user)).not.toBe(await linkedTodoId(e, other))
  })
})

describe('planLinkedTodos', () => {
  it('creates a todo for non-routine events from today on, mirroring title and day', async () => {
    const exam = event('MATH240 Midterm', 3, { kind: 'exam' })
    const gym = event('Gym', 1, { is_routine: true, kind: 'personal' })
    const past = event('Old dentist', -2, { kind: 'appointment' })
    const dentist = event('Dentist', 0, { kind: 'appointment' })
    const plan = await planLinkedTodos([exam, gym, past, dentist], [], user, today)
    expect(plan.deletes).toEqual([])
    expect(plan.upserts.map((u) => u.event_id).sort()).toEqual([exam.id, dentist.id].sort())
    const examTodo = plan.upserts.find((u) => u.event_id === exam.id)!
    expect(examTodo.id).toBe(await linkedTodoId(exam.id, user))
    expect(examTodo.title).toBe('MATH240 Midterm')
    expect(examTodo.day_key).toBe(today + 3)
    expect(examTodo.due_day_key).toBe(today + 3)
    expect(examTodo.priority).toBe(1)
    expect(examTodo.is_done).toBe(false)
  })

  it('plans nothing when everything is already in step', async () => {
    const e = event('Problem set', 1)
    const t = todo(e.id, { title: 'Problem set' })
    expect(await planLinkedTodos([e], [t], user, today)).toEqual({ upserts: [], deletes: [] })
  })

  it('follows a renamed and moved event but keeps a work day the member moved', async () => {
    const e = event('Problem set 3 (revised)', 3)
    const stillOnDueDay = todo(e.id, { title: 'Problem set 3' })
    let plan = await planLinkedTodos([e], [stillOnDueDay], user, today)
    expect(plan.upserts).toEqual([
      { id: stillOnDueDay.id, title: 'Problem set 3 (revised)', day_key: today + 3, week_key: null, due_day_key: today + 3 },
    ])

    const movedEarly = todo(e.id, { title: 'Problem set 3 (revised)', day_key: today, due_day_key: today + 1 })
    plan = await planLinkedTodos([e], [movedEarly], user, today)
    expect(plan.upserts).toEqual([{ id: movedEarly.id, due_day_key: today + 3 }])
  })

  it('tombstones todos whose event is gone or routine', async () => {
    const routine = event('Chess club', 1, { is_routine: true })
    const orphan = todo('gone-event')
    const forRoutine = todo(routine.id)
    const plan = await planLinkedTodos([routine], [orphan, forRoutine], user, today)
    expect(plan.deletes.sort()).toEqual([orphan.id, forRoutine.id].sort())
    expect(plan.upserts).toEqual([])
  })

  it('collapses duplicates onto the older todo without losing a tick', async () => {
    const e = event('Lab report', 1)
    const older = todo(e.id, { title: 'Lab report', created_at: '2026-09-01T00:00:00Z' })
    const newer = todo(e.id, {
      title: 'Lab report',
      created_at: '2026-09-02T00:00:00Z',
      is_done: true,
      completed_at: '2026-09-03T00:00:00Z',
    })
    const plan = await planLinkedTodos([e], [older, newer], user, today)
    expect(plan.deletes).toEqual([newer.id])
    expect(plan.upserts).toEqual([{ id: older.id, is_done: true, completed_at: '2026-09-03T00:00:00Z' }])
  })

  it('mirrors shared completion from the event onto the todo', async () => {
    const e = event('Group report', 1, {
      group_id: 'g',
      shared_completion: true,
      completed_at: '2026-10-01T12:00:00Z',
      completed_by: other,
    })
    const t = todo(e.id, { title: 'Group report' })
    const plan = await planLinkedTodos([e], [t], user, today)
    expect(plan.upserts).toEqual([{ id: t.id, is_done: true, completed_at: '2026-10-01T12:00:00Z' }])

    const reopened = { ...e, completed_at: null, completed_by: null }
    const doneTodo = { ...t, is_done: true, completed_at: '2026-10-01T12:00:00Z' }
    expect((await planLinkedTodos([reopened], [doneTodo], user, today)).upserts).toEqual([
      { id: t.id, is_done: false, completed_at: null },
    ])
  })

  it('leaves individual completion alone', async () => {
    const e = event('Problem set', 1, { group_id: 'g' })
    const done = todo(e.id, { title: 'Problem set', is_done: true, completed_at: '2026-10-01T12:00:00Z' })
    expect(await planLinkedTodos([e], [done], user, today)).toEqual({ upserts: [], deletes: [] })
  })
})
