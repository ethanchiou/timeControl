import { useMemo, useState } from 'react'
import {
  addingMonths,
  civil,
  monthGrid,
  today as todayKey,
  weekdayShortName,
  WEEKDAYS,
  type DayKey,
  type EventSpec,
  type Occurrence,
} from '@/core'
import { dayNumber, monthYearLabel } from '@/lib/format'
import { useEye } from '@/data/eye'
import { useStore } from '@/data/store'
import { useSchedule } from '@/features/useSchedule'
import { isToday } from '@/features/DayGrid'
import { EventSheet } from '@/features/EventSheet'
import { CalendarBar } from '@/ui/CalendarBar'
import { MonthPill, OccurrenceDetails } from '@/ui/occurrence'
import { Button, Sheet } from '@/ui/primitives'

/** How many items a cell shows before it collapses the rest into a count. */
const PILLS_PER_DAY = 3

export function Month() {
  const { data } = useStore()
  const [anchor, setAnchor] = useState<DayKey>(() => todayKey())
  const [filter, setFilter] = useEye('month')
  const [openOccurrence, setOpenOccurrence] = useState<Occurrence | null>(null)
  const [expanded, setExpanded] = useState<DayKey | null>(null)
  const [editing, setEditing] = useState<{ event: EventSpec | null; day: DayKey } | null>(null)

  const [gridStart, gridEnd] = useMemo(() => monthGrid(anchor), [anchor])
  const { hiddenCount, byDay } = useSchedule(gridStart, gridEnd, filter)
  const month = civil(anchor).month

  const weeks = useMemo(() => {
    const rows: DayKey[][] = []
    for (let day = gridStart; day <= gridEnd; day += 7) {
      rows.push([0, 1, 2, 3, 4, 5, 6].map((i) => day + i))
    }
    return rows
  }, [gridStart, gridEnd])

  return (
    <>
      <CalendarBar
        title={monthYearLabel(anchor)}
        onPrev={() => setAnchor(addingMonths(anchor, -1))}
        onNext={() => setAnchor(addingMonths(anchor, 1))}
        onToday={() => setAnchor(todayKey())}
        atToday={civil(anchor).month === civil(todayKey()).month && civil(anchor).year === civil(todayKey()).year}
        filter={filter}
        onFilterChange={setFilter}
        hiddenCount={hiddenCount}
        onAdd={() => setEditing({ event: null, day: todayKey() })}
      />

      <div className="flex min-h-0 flex-1 flex-col">
        <div className="grid shrink-0 grid-cols-7 border-b border-line bg-surface">
          {WEEKDAYS.map((w) => (
            <div key={w} className="py-1 text-center text-micro text-muted">
              {weekdayShortName(w)}
            </div>
          ))}
        </div>

        <div
          className="grid min-h-0 flex-1 overflow-y-auto"
          style={{ gridTemplateRows: `repeat(${weeks.length}, minmax(88px, 1fr))` }}
        >
          {weeks.map((row) => (
            <div key={row[0]} className="grid grid-cols-7 border-b border-line">
              {row.map((day) => {
                const items = byDay.get(day) ?? []
                const overflow = items.length - PILLS_PER_DAY
                const outside = civil(day).month !== month
                return (
                  <div
                    key={day}
                    className={`flex min-w-0 flex-col gap-px border-l border-line px-1 py-1 first:border-l-0 ${
                      outside ? 'bg-bg' : ''
                    }`}
                  >
                    <button
                      type="button"
                      onClick={() => setEditing({ event: null, day })}
                      title="New event"
                      className={`num self-start rounded px-1 text-tiny hover:bg-sunken ${
                        isToday(day)
                          ? 'bg-accent font-semibold text-[color:var(--accent-ink)] hover:brightness-110'
                          : outside
                            ? 'text-faint'
                            : 'text-muted'
                      }`}
                    >
                      {dayNumber(day)}
                    </button>
                    {items.slice(0, PILLS_PER_DAY).map((o) => (
                      <MonthPill key={o.id} occurrence={o} onOpen={() => setOpenOccurrence(o)} />
                    ))}
                    {overflow > 0 ? (
                      <button
                        type="button"
                        onClick={() => setExpanded(day)}
                        className="num self-start px-1 text-micro text-muted hover:text-ink"
                      >
                        +{overflow} more
                      </button>
                    ) : null}
                  </div>
                )
              })}
            </div>
          ))}
        </div>
      </div>

      {expanded !== null ? (
        <Sheet title={monthYearLabel(expanded)} onClose={() => setExpanded(null)}>
          <div className="flex flex-col gap-1">
            {(byDay.get(expanded) ?? []).map((o) => (
              <MonthPill
                key={o.id}
                occurrence={o}
                onOpen={() => {
                  setExpanded(null)
                  setOpenOccurrence(o)
                }}
              />
            ))}
          </div>
        </Sheet>
      ) : null}

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
        <EventSheet event={editing.event} defaultDay={editing.day} onClose={() => setEditing(null)} />
      ) : null}
    </>
  )
}
