import { useMemo, useState } from 'react'
import { ArrowLeftIcon, ArrowRightIcon, PlusIcon } from '@phosphor-icons/react'
import {
  dailyProgress,
  listOrder,
  progressOf,
  today as todayKey,
  weekStart,
  type DayKey,
  type TodoSpec,
} from '@/core'
import { useStore } from '@/data/store'
import { TodoRow } from '@/features/TodoRow'
import { TodoSheet } from '@/features/TodoSheet'
import { Button, EmptyState, Ring, SkeletonRows } from '@/ui/primitives'

type Column = 'today' | 'week' | 'backlog'

const COLUMNS: Array<{ id: Column; title: string; hint: string }> = [
  { id: 'today', title: 'Today', hint: 'What you are doing now' },
  { id: 'week', title: 'This week', hint: 'Somewhere in the next seven days' },
  { id: 'backlog', title: 'Backlog', hint: 'Not scheduled yet' },
]

/** Where a todo belongs. Every todo lands in exactly one column. */
function columnOf(todo: TodoSpec, today: DayKey, monday: DayKey): Column {
  if (todo.day === today) return 'today'
  if (todo.week === monday) return 'week'
  if (todo.day !== null && todo.day >= monday && todo.day <= monday + 6) return 'week'
  return 'backlog'
}

/** What moving into a column sets. A todo is on a day, in a week, or in neither. */
function bucketFor(column: Column, today: DayKey, monday: DayKey) {
  switch (column) {
    case 'today':
      return { dayKey: today, weekKey: null }
    case 'week':
      return { dayKey: null, weekKey: monday }
    case 'backlog':
      return { dayKey: null, weekKey: null }
  }
}

export function Todos() {
  const { data, loading, saveTodo } = useStore()
  const [adding, setAdding] = useState<Column | null>(null)

  const today = todayKey()
  const monday = weekStart(today)

  const byColumn = useMemo(() => {
    const buckets: Record<Column, TodoSpec[]> = { today: [], week: [], backlog: [] }
    for (const todo of data.todos) buckets[columnOf(todo, today, monday)].push(todo)
    for (const key of Object.keys(buckets) as Column[]) buckets[key].sort(listOrder)
    return buckets
  }, [data.todos, today, monday])

  async function move(todo: TodoSpec, to: Column) {
    const bucket = bucketFor(to, today, monday)
    await saveTodo({
      id: todo.id,
      title: todo.title,
      notes: todo.notes,
      priority: todo.priority,
      isDone: todo.isDone,
      dayKey: bucket.dayKey,
      weekKey: bucket.weekKey,
      dueDayKey: todo.dueDay,
      projectId: todo.projectId,
    })
  }

  return (
    <>
      <header className="flex shrink-0 items-center gap-2 border-b border-line bg-surface px-3 py-2">
        <h1 className="mr-auto text-lg font-semibold tracking-tight">Todos</h1>
        <Ring
          done={dailyProgress(data.todos, today).done}
          total={dailyProgress(data.todos, today).total}
          size={28}
        />
        <Button tone="primary" onClick={() => setAdding('today')} className="h-7 px-2 text-tiny">
          <PlusIcon size={13} weight="bold" />
          New todo
        </Button>
      </header>

      <div className="grid min-h-0 flex-1 grid-cols-1 overflow-y-auto lg:grid-cols-3 lg:overflow-hidden">
        {COLUMNS.map((column, index) => {
          const todos = byColumn[column.id]
          const progress = progressOf(todos)
          return (
            <section
              key={column.id}
              className={`flex min-h-0 flex-col ${index > 0 ? 'border-t border-line lg:border-l lg:border-t-0' : ''}`}
            >
              <header className="flex shrink-0 items-center gap-2 border-b border-line px-3 py-2">
                <div className="mr-auto min-w-0">
                  <p className="text-base font-medium">{column.title}</p>
                  <p className="text-tiny text-faint">{column.hint}</p>
                </div>
                <span className="num text-tiny text-muted">
                  {progress.total === 0 ? '' : `${progress.done}/${progress.total}`}
                </span>
                <button
                  type="button"
                  aria-label={`New todo in ${column.title}`}
                  title={`New todo in ${column.title}`}
                  onClick={() => setAdding(column.id)}
                  className="flex h-6 w-6 items-center justify-center rounded text-muted hover:bg-sunken hover:text-ink"
                >
                  <PlusIcon size={13} weight="bold" />
                </button>
              </header>

              <div className="min-h-0 flex-1 lg:overflow-y-auto">
                {loading ? (
                  <SkeletonRows count={3} />
                ) : todos.length === 0 ? (
                  <EmptyState title="Nothing here" />
                ) : (
                  todos.map((todo) => (
                    <div key={todo.id} className="group/row relative">
                      <TodoRow todo={todo} />
                      <div className="pointer-events-none absolute inset-y-0 right-2 hidden items-center gap-0.5 group-hover/row:flex lg:flex lg:opacity-0 lg:transition-opacity lg:duration-150 lg:group-hover/row:opacity-100">
                        {index > 0 ? (
                          <MoveButton
                            label={`Move to ${COLUMNS[index - 1]!.title}`}
                            onClick={() => void move(todo, COLUMNS[index - 1]!.id)}
                          >
                            <ArrowLeftIcon size={12} />
                          </MoveButton>
                        ) : null}
                        {index < COLUMNS.length - 1 ? (
                          <MoveButton
                            label={`Move to ${COLUMNS[index + 1]!.title}`}
                            onClick={() => void move(todo, COLUMNS[index + 1]!.id)}
                          >
                            <ArrowRightIcon size={12} />
                          </MoveButton>
                        ) : null}
                      </div>
                    </div>
                  ))
                )}
              </div>
            </section>
          )
        })}
      </div>

      {adding ? (
        <TodoSheet
          todo={null}
          bucket={bucketFor(adding, today, monday)}
          onClose={() => setAdding(null)}
        />
      ) : null}
    </>
  )
}

function MoveButton({
  label,
  onClick,
  children,
}: {
  label: string
  onClick: () => void
  children: React.ReactNode
}) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      onClick={onClick}
      className="pointer-events-auto flex h-6 w-6 items-center justify-center rounded border border-line bg-surface text-muted hover:border-line-strong hover:text-ink"
    >
      {children}
    </button>
  )
}
