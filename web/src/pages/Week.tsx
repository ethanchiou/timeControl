import { useMemo, useState } from 'react'
import { CheckSquareIcon } from '@phosphor-icons/react'
import {
  today as todayKey,
  weekStart,
  type DayKey,
  type EventSpec,
  type Occurrence,
  type TodoSpec,
} from '@/core'
import { dayNumber, monthYearLabel, weekdayShortLabel } from '@/lib/format'
import { useEye } from '@/data/eye'
import { useStore } from '@/data/store'
import { useSchedule, useTermContext } from '@/features/useSchedule'
import { DayColumn, HourGutter, HOUR_HEIGHT, isToday, useScrollToFirst } from '@/features/DayGrid'
import { EventSheet } from '@/features/EventSheet'
import { CalendarBar } from '@/ui/CalendarBar'
import { AllDayPill, OccurrenceDetails } from '@/ui/occurrence'
import { Button, Sheet, SkeletonRows } from '@/ui/primitives'

export function Week() {
  const { data, loading } = useStore()
  const [monday, setMonday] = useState<DayKey>(() => weekStart(todayKey()))
  const [filter, setFilter] = useEye('week')
  const [openOccurrence, setOpenOccurrence] = useState<Occurrence | null>(null)
  const [editing, setEditing] = useState<{ event: EventSpec | null; day: DayKey } | null>(null)

  const days = useMemo(() => [0, 1, 2, 3, 4, 5, 6].map((i) => monday + i), [monday])
  const sunday = monday + 6
  const { shown, hiddenCount, byDay } = useSchedule(monday, sunday, filter)
  const { term, week, weeks } = useTermContext(isToday(monday) ? monday : monday + 3)

  const scroller = useScrollToFirst(shown, !loading)

  const dueByDay = useMemo(() => {
    const map = new Map<DayKey, TodoSpec[]>()
    for (const todo of data.todos) {
      if (todo.dueDay === null || todo.isDone) continue
      if (todo.dueDay < monday || todo.dueDay > sunday) continue
      const bucket = map.get(todo.dueDay)
      if (bucket) bucket.push(todo)
      else map.set(todo.dueDay, [todo])
    }
    return map
  }, [data.todos, monday, sunday])

  const anyAllDay = days.some(
    (day) => (byDay.get(day) ?? []).some((o) => o.isAllDay) || (dueByDay.get(day)?.length ?? 0) > 0,
  )

  const monthLabel =
    monthYearLabel(monday) === monthYearLabel(sunday)
      ? monthYearLabel(monday)
      : `${monthYearLabel(monday)} to ${monthYearLabel(sunday)}`

  return (
    <>
      <CalendarBar
        title={monthLabel}
        subtitle={term && week !== null ? `${term.name}, week ${week} of ${weeks}` : undefined}
        onPrev={() => setMonday(monday - 7)}
        onNext={() => setMonday(monday + 7)}
        onToday={() => setMonday(weekStart(todayKey()))}
        atToday={monday === weekStart(todayKey())}
        filter={filter}
        onFilterChange={setFilter}
        hiddenCount={hiddenCount}
        onAdd={() => setEditing({ event: null, day: todayKey() })}
      />

      <div ref={scroller} className="min-h-0 flex-1 overflow-auto">
        <div className="min-w-[680px]">
          {/* Day names and numbers, pinned so the grid keeps its labels while it scrolls. */}
          <div className="sticky top-0 z-20 flex border-b border-line bg-surface">
            <div className="w-[52px] shrink-0" />
            {days.map((day) => (
              <div
                key={day}
                className="flex flex-1 items-baseline justify-center gap-1.5 border-l border-line py-1.5"
              >
                <span className="text-tiny text-muted">{weekdayShortLabel(day)}</span>
                <span
                  className={`num text-base ${
                    isToday(day)
                      ? 'flex h-[22px] min-w-[22px] items-center justify-center rounded-full bg-accent px-1 font-semibold text-[color:var(--accent-ink)]'
                      : 'font-medium'
                  }`}
                >
                  {dayNumber(day)}
                </span>
              </div>
            ))}
          </div>

          {anyAllDay ? (
            <div className="flex border-b border-line bg-surface">
              <div className="num w-[52px] shrink-0 py-1 pr-1.5 text-right text-micro text-faint">
                all day
              </div>
              {days.map((day) => (
                <div key={day} className="flex flex-1 flex-col gap-1 border-l border-line p-1">
                  {(byDay.get(day) ?? [])
                    .filter((o) => o.isAllDay)
                    .map((o) => (
                      <AllDayPill key={o.id} occurrence={o} onOpen={() => setOpenOccurrence(o)} />
                    ))}
                  {(dueByDay.get(day) ?? []).map((todo) => (
                    <span
                      key={todo.id}
                      title={`Due: ${todo.title}`}
                      className="flex items-center gap-1 rounded-full bg-sunken px-2 py-0.5 text-micro text-muted"
                    >
                      <CheckSquareIcon size={10} />
                      <span className="truncate">{todo.title}</span>
                    </span>
                  ))}
                </div>
              ))}
            </div>
          ) : null}

          {loading ? (
            <SkeletonRows count={8} />
          ) : (
            <div className="flex pb-6" style={{ minHeight: 24 * HOUR_HEIGHT }}>
              <HourGutter />
              {days.map((day) => (
                <div key={day} className="flex flex-1 border-l border-line">
                  <DayColumn
                    day={day}
                    occurrences={(byDay.get(day) ?? []).filter((o) => !o.isAllDay)}
                    onOpen={setOpenOccurrence}
                    showNowLine={isToday(day)}
                  />
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {openOccurrence ? (
        <Sheet
          title="Details"
          onClose={() => setOpenOccurrence(null)}
          footer={
            openOccurrence.source.type === 'event' ? (
              <Button
                onClick={() => {
                  const id =
                    openOccurrence.source.type === 'event' ? openOccurrence.source.eventId : null
                  const event = data.events.find((e) => e.id === id) ?? null
                  const day = openOccurrence.day
                  setOpenOccurrence(null)
                  setEditing({ event, day })
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
        <EventSheet
          event={editing.event}
          defaultDay={editing.day}
          onClose={() => setEditing(null)}
        />
      ) : null}
    </>
  )
}
