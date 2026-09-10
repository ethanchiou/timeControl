import { useMemo, useState } from 'react'
import {
  dailyProgress,
  listOrder,
  today as todayKey,
  type DayKey,
  type EventSpec,
  type Occurrence,
} from '@/core'
import { fullDateLabel, weekdayLongLabel } from '@/lib/format'
import { useEye } from '@/data/eye'
import { useStore } from '@/data/store'
import { useSchedule, useTermContext } from '@/features/useSchedule'
import { DayColumn, HourGutter, HOUR_HEIGHT, isToday, useScrollToFirst } from '@/features/DayGrid'
import { EventSheet } from '@/features/EventSheet'
import { TodoRow } from '@/features/TodoRow'
import { CalendarBar } from '@/ui/CalendarBar'
import { AllDayPill, OccurrenceDetails } from '@/ui/occurrence'
import { Button, EmptyState, Ring, Sheet, SkeletonRows } from '@/ui/primitives'

export function Today() {
  const { data, loading } = useStore()
  const [day, setDay] = useState<DayKey>(() => todayKey())
  const [filter, setFilter] = useEye('day')
  const [openOccurrence, setOpenOccurrence] = useState<Occurrence | null>(null)
  const [editing, setEditing] = useState<{ event: EventSpec | null } | null>(null)

  const { shown, hiddenCount } = useSchedule(day, day, filter)
  const { term, week, weeks } = useTermContext(day)

  const allDay = shown.filter((o) => o.isAllDay)
  const timed = shown.filter((o) => !o.isAllDay)
  const scroller = useScrollToFirst(timed, !loading)

  const dayTodos = useMemo(
    () => data.todos.filter((t) => t.day === day).sort(listOrder),
    [data.todos, day],
  )
  const progress = useMemo(() => dailyProgress(data.todos, day), [data.todos, day])

  const subtitle = term ? `${term.name}, week ${week} of ${weeks}` : undefined

  return (
    <>
      <CalendarBar
        title={isToday(day) ? 'Today' : weekdayLongLabel(day)}
        subtitle={[fullDateLabel(day), subtitle].filter(Boolean).join(' · ')}
        onPrev={() => setDay(day - 1)}
        onNext={() => setDay(day + 1)}
        onToday={() => setDay(todayKey())}
        atToday={isToday(day)}
        filter={filter}
        onFilterChange={setFilter}
        hiddenCount={hiddenCount}
        onAdd={() => setEditing({ event: null })}
      />

      <div className="flex min-h-0 flex-1 flex-col xl:flex-row">
        <section className="flex min-h-0 flex-1 flex-col">
          {allDay.length > 0 ? (
            <div className="flex shrink-0 flex-wrap gap-1.5 border-b border-line px-3 py-2">
              {allDay.map((o) => (
                <AllDayPill key={o.id} occurrence={o} onOpen={() => setOpenOccurrence(o)} />
              ))}
            </div>
          ) : null}

          {loading ? (
            <SkeletonRows count={6} />
          ) : timed.length === 0 && allDay.length === 0 ? (
            <EmptyState
              title="Nothing scheduled"
              hint={
                hiddenCount > 0
                  ? `The eye is hiding ${hiddenCount}.`
                  : 'Add an event, or set up a term so your courses land here.'
              }
            />
          ) : (
            <div ref={scroller} className="min-h-0 flex-1 overflow-y-auto">
              <div className="flex px-3 pb-6" style={{ minHeight: 24 * HOUR_HEIGHT }}>
                <HourGutter />
                <DayColumn
                  day={day}
                  occurrences={timed}
                  onOpen={setOpenOccurrence}
                  showNowLine={isToday(day)}
                />
              </div>
            </div>
          )}
        </section>

        <section className="flex min-h-0 shrink-0 flex-col border-t border-line xl:w-[320px] xl:border-l xl:border-t-0">
          <header className="flex shrink-0 items-center gap-2.5 border-b border-line px-3 py-2">
            <Ring done={progress.done} total={progress.total} />
            <div className="min-w-0 flex-1">
              <p className="text-base font-medium">Todos</p>
              <p className="num text-tiny text-muted">
                {progress.total === 0
                  ? 'Nothing due'
                  : `${progress.total - progress.done} left of ${progress.total}`}
              </p>
            </div>
          </header>
          <div className="min-h-0 flex-1 overflow-y-auto">
            {loading ? (
              <SkeletonRows count={3} />
            ) : dayTodos.length === 0 ? (
              <EmptyState title="Nothing due today" />
            ) : (
              dayTodos.map((todo) => <TodoRow key={todo.id} todo={todo} />)
            )}
          </div>
        </section>
      </div>

      {openOccurrence ? (
        <Sheet
          title="Details"
          onClose={() => setOpenOccurrence(null)}
          footer={
            openOccurrence.source.type === 'event' ? (
              <Button
                onClick={() => {
                  const id = openOccurrence.source.type === 'event' ? openOccurrence.source.eventId : null
                  const event = data.events.find((e) => e.id === id) ?? null
                  setOpenOccurrence(null)
                  setEditing({ event })
                }}
              >
                Edit
              </Button>
            ) : (
              <p className="text-tiny text-faint">Courses are edited in the native app.</p>
            )
          }
        >
          <OccurrenceDetails occurrence={openOccurrence} />
        </Sheet>
      ) : null}

      {editing ? (
        <EventSheet event={editing.event} defaultDay={day} onClose={() => setEditing(null)} />
      ) : null}
    </>
  )
}
