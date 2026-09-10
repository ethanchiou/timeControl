import { useState } from 'react'
import { TrashIcon } from '@phosphor-icons/react'
import { dayKey, type DayKey, type TodoSpec } from '@/core'
import { dayToInputValue } from '@/lib/format'
import { friendlyError } from '@/lib/supabase'
import { newId, useStore } from '@/data/store'
import { Button, ErrorNote, Field, Select, Sheet, TextInput } from '@/ui/primitives'

const PRIORITIES = [
  { value: 1, label: '1, urgent' },
  { value: 2, label: '2, high' },
  { value: 3, label: '3, normal' },
  { value: 4, label: '4, low' },
]

function parseDateInput(value: string): DayKey | null {
  const parts = value.split('-').map(Number)
  if (parts.length !== 3 || parts.some((n) => !Number.isFinite(n))) return null
  return dayKey(parts[0]!, parts[1]!, parts[2]!)
}

export function TodoSheet({
  todo,
  bucket,
  onClose,
}: {
  /** null creates a new todo in `bucket`. */
  todo: TodoSpec | null
  bucket?: { dayKey: DayKey | null; weekKey: DayKey | null }
  onClose: () => void
}) {
  const { data, saveTodo, deleteTodo } = useStore()
  const [title, setTitle] = useState(todo?.title ?? '')
  const [priority, setPriority] = useState(todo?.priority ?? 3)
  const [dueDay, setDueDay] = useState<DayKey | null>(todo?.dueDay ?? null)
  const [projectId, setProjectId] = useState<string | null>(todo?.projectId ?? null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function save() {
    if (!title.trim() || busy) return
    setBusy(true)
    const { error: failure } = await saveTodo({
      id: todo?.id ?? newId(),
      title: title.trim(),
      notes: todo?.notes ?? '',
      priority,
      isDone: todo?.isDone ?? false,
      dayKey: todo ? todo.day : (bucket?.dayKey ?? null),
      weekKey: todo ? todo.week : (bucket?.weekKey ?? null),
      dueDayKey: dueDay,
      projectId,
    })
    setBusy(false)
    if (failure) setError(friendlyError(failure))
    else onClose()
  }

  async function remove() {
    if (!todo) return
    setBusy(true)
    const { error: failure } = await deleteTodo(todo.id)
    setBusy(false)
    if (failure) setError(friendlyError(failure))
    else onClose()
  }

  return (
    <Sheet
      title={todo ? 'Edit todo' : 'New todo'}
      onClose={onClose}
      onSubmit={save}
      footer={
        <>
          {todo ? (
            <Button tone="danger" className="mr-auto" onClick={remove} disabled={busy}>
              <TrashIcon size={14} />
              Delete
            </Button>
          ) : null}
          <Button tone="quiet" onClick={onClose}>
            Cancel
          </Button>
          <Button tone="primary" onClick={save} disabled={!title.trim() || busy}>
            Save
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-3">
        {error ? <ErrorNote>{error}</ErrorNote> : null}
        <Field label="Title">
          <TextInput
            autoFocus
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Finish problem set 4"
          />
        </Field>
        <div className="grid grid-cols-2 gap-3">
          <Field label="Priority">
            <Select value={priority} onChange={(e) => setPriority(Number(e.target.value))}>
              {PRIORITIES.map((p) => (
                <option key={p.value} value={p.value}>
                  {p.label}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Due">
            <TextInput
              type="date"
              value={dueDay === null ? '' : dayToInputValue(dueDay)}
              onChange={(e) =>
                setDueDay(e.target.value === '' ? null : parseDateInput(e.target.value))
              }
            />
          </Field>
        </div>
        <Field label="Project" hint="Projects are created in the native app.">
          <Select
            value={projectId ?? ''}
            onChange={(e) => setProjectId(e.target.value === '' ? null : e.target.value)}
          >
            <option value="">No project</option>
            {data.projects.map((p) => (
              <option key={p.id} value={p.id}>
                {p.title}
              </option>
            ))}
          </Select>
        </Field>
      </div>
    </Sheet>
  )
}
