/** Progress-ring aggregation for todos, bucketed by day, week or project. From `RingMath.swift`. */

import { weekStart, type DayKey } from './dayKey'
import type { TodoSpec } from './specs'

export interface RingProgress {
  readonly done: number
  readonly total: number
}

/** Clamps `done` into `0...total`; `total` is floored at 0. */
export function ringProgress(done: number, total: number): RingProgress {
  const clampedTotal = Math.max(0, total)
  return { total: clampedTotal, done: Math.min(Math.max(0, done), clampedTotal) }
}

export const EMPTY_PROGRESS: RingProgress = { done: 0, total: 0 }

/** Fraction complete, 0 when `total` is 0. */
export function fraction(p: RingProgress): number {
  return p.total === 0 ? 0 : p.done / p.total
}

export function isComplete(p: RingProgress): boolean {
  return p.total > 0 && p.done === p.total
}

export function isEmptyProgress(p: RingProgress): boolean {
  return p.total === 0
}

export function remaining(p: RingProgress): number {
  return p.total - p.done
}

/** Plain done/total over any todos. */
export function progressOf(todos: readonly TodoSpec[]): RingProgress {
  let done = 0
  for (const t of todos) if (t.isDone) done += 1
  return ringProgress(done, todos.length)
}

/** Todos whose `day` is exactly `day`. */
export function dailyProgress(todos: readonly TodoSpec[], day: DayKey): RingProgress {
  return progressOf(todos.filter((t) => t.day === day))
}

/**
 * Todos bucketed into the week of `day`, plus todos whose `day` falls in that week.
 * `day` may be any day in the week; it is normalised to its Monday.
 */
export function weeklyProgress(todos: readonly TodoSpec[], day: DayKey): RingProgress {
  const monday = weekStart(day)
  const sunday = monday + 6
  return progressOf(
    todos.filter((t) => {
      if (t.week === monday) return true
      return t.day !== null && t.day >= monday && t.day <= sunday
    }),
  )
}

/** Todos belonging to one project. */
export function projectProgress(todos: readonly TodoSpec[], projectId: string): RingProgress {
  return progressOf(todos.filter((t) => t.projectId === projectId))
}

/** Sort order for a list: open before done, then priority ascending (1 first). */
export function listOrder(a: TodoSpec, b: TodoSpec): number {
  if (a.isDone !== b.isDone) return a.isDone ? 1 : -1
  if (a.priority !== b.priority) return a.priority - b.priority
  return a.sortOrder - b.sortOrder
}
