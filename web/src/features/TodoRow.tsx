import { useState } from 'react'
import { CheckIcon } from '@phosphor-icons/react'
import { today as todayKey, type TodoSpec } from '@/core'
import { relativeDayLabel } from '@/lib/format'
import { useStore } from '@/data/store'
import { ColorDot } from '@/ui/primitives'
import { TodoSheet } from './TodoSheet'

/** 1 is urgent. Only the top two priorities earn ink; the rest would just be noise. */
function PriorityMark({ priority }: { priority: number }) {
  if (priority > 2) return null
  return (
    <span
      className="num rounded-full px-1.5 py-px text-micro font-medium"
      style={{
        background: priority === 1 ? 'color-mix(in oklab, #E5484D 16%, transparent)' : 'var(--sunken)',
        color: priority === 1 ? '#E5484D' : 'var(--muted)',
      }}
    >
      P{priority}
    </span>
  )
}

export function TodoRow({ todo, showDue = true }: { todo: TodoSpec; showDue?: boolean }) {
  const { data, setTodoDone } = useStore()
  const [editing, setEditing] = useState(false)
  const project = todo.projectId ? data.projects.find((p) => p.id === todo.projectId) : undefined

  return (
    <>
      <div className="group flex items-start gap-2 border-b border-line px-3 py-2 transition-colors duration-150 hover:bg-sunken">
        <button
          type="button"
          role="checkbox"
          aria-checked={todo.isDone}
          aria-label={todo.isDone ? `Mark ${todo.title} not done` : `Mark ${todo.title} done`}
          onClick={() => void setTodoDone(todo.id, !todo.isDone)}
          className={`mt-px flex h-[15px] w-[15px] shrink-0 items-center justify-center rounded-[4px] border transition-colors duration-150 ${
            todo.isDone ? 'border-accent bg-accent' : 'border-line-strong hover:border-accent'
          }`}
        >
          {todo.isDone ? <CheckIcon size={10} weight="bold" color="var(--accent-ink)" /> : null}
        </button>

        <button
          type="button"
          onClick={() => setEditing(true)}
          className="flex min-w-0 flex-1 flex-col items-start gap-0.5 text-left"
        >
          <span
            className={`text-base ${todo.isDone ? 'text-faint line-through' : ''}`}
          >
            {todo.title || 'Untitled'}
          </span>
          {(project || (showDue && todo.dueDay !== null)) && !todo.isDone ? (
            <span className="flex flex-wrap items-center gap-x-2 gap-y-0.5 text-tiny text-muted">
              {project ? (
                <span className="inline-flex items-center gap-1">
                  <ColorDot hex={project.colorHex} size={6} />
                  {project.title}
                </span>
              ) : null}
              {showDue && todo.dueDay !== null ? (
                <span className={todo.dueDay < todayKey() ? 'text-danger' : undefined}>
                  due {relativeDayLabel(todo.dueDay, todayKey())}
                </span>
              ) : null}
            </span>
          ) : null}
        </button>

        <PriorityMark priority={todo.priority} />
      </div>

      {editing ? <TodoSheet todo={todo} onClose={() => setEditing(false)} /> : null}
    </>
  )
}
