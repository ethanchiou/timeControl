/**
 * One todo per non-routine event, mirroring `EventTaskLinker.swift`. The todo is the member's
 * completion record for the event: ticking it finishes the event for them (and for everyone when
 * the event shares completion). Its title and due day follow the event; the day the member plans to
 * work on it is theirs. Routine events get none.
 *
 * `planLinkedTodos` is pure: it takes what the store read and returns the writes that bring the
 * todos in step. The store applies them and reloads. Idempotent, so a second pass plans nothing.
 */

import { dayKeyOf, type DayKey } from '@/core'
import type { EventRow, TodoRow } from './rows'

/** Fixed forever, shared with the native app: a different value would give every event a second todo. */
export const LINKED_TODO_NAMESPACE = '5d2c8f1e-7a3b-4c6d-9e0f-1a2b3c4d5e6f'

function uuidBytes(uuid: string): Uint8Array {
  const hex = uuid.replace(/-/g, '')
  const out = new Uint8Array(16)
  for (let i = 0; i < 16; i += 1) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16)
  return out
}

function formatUuid(bytes: Uint8Array): string {
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`
}

/** RFC 4122 version 5: SHA-1 of the namespace and the name, with the version and variant bits set. */
export async function uuid5(namespace: string, name: string): Promise<string> {
  const ns = uuidBytes(namespace)
  const text = new TextEncoder().encode(name)
  const input = new Uint8Array(ns.length + text.length)
  input.set(ns, 0)
  input.set(text, ns.length)
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-1', input)).slice(0, 16)
  digest[6] = (digest[6]! & 0x0f) | 0x50
  digest[8] = (digest[8]! & 0x3f) | 0x80
  return formatUuid(digest)
}

/** The id of `userId`'s todo for `eventId`; every device of one account derives the same one. */
export function linkedTodoId(eventId: string, userId: string): Promise<string> {
  return uuid5(LINKED_TODO_NAMESPACE, `${eventId.toLowerCase()}|${userId.toLowerCase()}`)
}

export interface LinkedTodoPlan {
  /** Whole rows to upsert (new todos) or the changed columns of existing ones, each with its `id`. */
  upserts: Array<Partial<TodoRow> & { id: string }>
  /** Todos to tombstone: their event is gone, became routine, or they duplicate another. */
  deletes: string[]
}

const EMPTY_PLAN: LinkedTodoPlan = { upserts: [], deletes: [] }

/** Exams outrank assignments outrank the rest. */
export function defaultPriority(kind: string): number {
  switch (kind) {
    case 'exam':
      return 1
    case 'assignment':
    case 'interview':
      return 2
    default:
      return 3
  }
}

/**
 * `events` and `todos` are the live rows (tombstones already filtered out). Only events from today
 * on get a new todo; an event already tracked keeps its todo whatever its date.
 */
export async function planLinkedTodos(
  events: readonly EventRow[],
  todos: readonly TodoRow[],
  userId: string,
  today: DayKey,
): Promise<LinkedTodoPlan> {
  const eventsById = new Map(events.map((e) => [e.id, e]))
  const linked = new Map<string, TodoRow>()
  const plan: LinkedTodoPlan = { upserts: [], deletes: [] }

  for (const todo of todos) {
    if (!todo.event_id) continue
    const event = eventsById.get(todo.event_id)
    if (!event || event.is_routine) {
      plan.deletes.push(todo.id)
      continue
    }
    const other = linked.get(todo.event_id)
    if (other) {
      // Two todos for one event, made on two devices before either saw the other. Keep the older.
      const [keep, drop] = (other.created_at ?? '') <= (todo.created_at ?? '') ? [other, todo] : [todo, other]
      if (drop.is_done && !keep.is_done) {
        plan.upserts.push({ id: keep.id, is_done: true, completed_at: drop.completed_at })
      }
      plan.deletes.push(drop.id)
      linked.set(todo.event_id, keep)
      continue
    }
    linked.set(todo.event_id, todo)
  }

  for (const event of events) {
    const day = dayKeyOf(new Date(event.start_at))
    const todo = linked.get(event.id)
    if (todo) {
      const patch = mirror(event, day, todo)
      if (patch) plan.upserts.push({ id: todo.id, ...patch })
    } else if (!event.is_routine && day >= today) {
      const shared = event.shared_completion ?? false
      plan.upserts.push({
        id: await linkedTodoId(event.id, userId),
        user_id: userId,
        project_id: null,
        title: event.title,
        notes: '',
        priority: defaultPriority(event.kind),
        is_done: shared && event.completed_at !== null,
        completed_at: shared ? event.completed_at : null,
        day_key: day,
        week_key: null,
        due_day_key: day,
        sort_order: 0,
        event_id: event.id,
      })
    }
  }

  return plan.upserts.length === 0 && plan.deletes.length === 0 ? EMPTY_PLAN : plan
}

/**
 * Title and due day follow the event. When the event moves, the work-on day moves with it only if
 * it was still on the old due day. A shared-completion event's done state is the event's.
 */
function mirror(event: EventRow, day: DayKey, todo: TodoRow): Partial<TodoRow> | null {
  const patch: Partial<TodoRow> = {}
  if (todo.title !== event.title) patch.title = event.title
  if (todo.due_day_key !== day) {
    if (todo.day_key === todo.due_day_key) {
      patch.day_key = day
      patch.week_key = null
    }
    patch.due_day_key = day
  }
  if (event.shared_completion) {
    const done = event.completed_at !== null
    if (todo.is_done !== done) {
      patch.is_done = done
      patch.completed_at = done ? event.completed_at : null
    }
  }
  return Object.keys(patch).length === 0 ? null : patch
}
