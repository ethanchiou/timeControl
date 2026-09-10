import { useMemo } from 'react'
import { MapPinIcon } from '@phosphor-icons/react'
import {
  kindColor,
  kindName,
  occurrenceColor,
  termSpecWeeks,
  today as todayKey,
  weekCount,
  weekdayShortName,
  weekNumber,
  type BlackoutSpec,
  type SeriesSpec,
  type TermSpec,
} from '@/core'
import { dayMonthLabel, minuteLabel } from '@/lib/format'
import { useStore } from '@/data/store'
import { ColorDot, EmptyState, SkeletonRows } from '@/ui/primitives'

/** "Mon/Wed 10:00-11:30", the way a timetable would print it. */
function scheduleSummary(series: SeriesSpec): string {
  const days = series.weekdays.map(weekdayShortName).join('/')
  return `${days || 'No day'} ${minuteLabel(series.startMinute)}-${minuteLabel(series.endMinute)}`
}

function weeksSummary(series: SeriesSpec, total: number): string {
  const every = series.intervalWeeks > 1 ? `every ${series.intervalWeeks} weeks, ` : ''
  if (series.startWeek === 1 && series.endWeek >= total) return `${every}all ${total} weeks`
  return `${every}weeks ${series.startWeek} to ${series.endWeek}`
}

export function Terms() {
  const { data, loading } = useStore()
  const today = todayKey()

  const terms = useMemo(
    () =>
      data.terms.map((term) => ({
        term,
        series: data.series
          .filter((s) => s.term.id === term.id)
          .sort((a, b) => a.startMinute - b.startMinute || a.title.localeCompare(b.title)),
        blackouts: data.blackouts
          .filter((b) => b.start >= term.start && b.start <= term.end)
          .sort((a, b) => a.start - b.start),
      })),
    [data.terms, data.series, data.blackouts],
  )

  return (
    <>
      <header className="flex shrink-0 items-baseline gap-2 border-b border-line bg-surface px-3 py-2">
        <h1 className="text-lg font-semibold tracking-tight">Terms</h1>
        <p className="text-tiny text-muted">Read only here. Set terms up in the native app.</p>
      </header>

      <div className="min-h-0 flex-1 overflow-y-auto">
        {loading ? (
          <SkeletonRows count={4} />
        ) : terms.length === 0 ? (
          <EmptyState
            title="No terms yet"
            hint="Create a term in the native app and its courses appear on your calendar here."
          />
        ) : (
          terms.map(({ term, series, blackouts }) => (
            <TermSection
              key={term.id}
              term={term}
              series={series}
              blackouts={blackouts}
              current={today >= term.start && today <= term.end}
            />
          ))
        )}
      </div>
    </>
  )
}

function TermSection({
  term,
  series,
  blackouts,
  current,
}: {
  term: TermSpec
  series: SeriesSpec[]
  blackouts: BlackoutSpec[]
  current: boolean
}) {
  const weeks = termSpecWeeks(term)
  const total = weekCount(weeks)
  const week = weekNumber(weeks, todayKey())

  return (
    <section className="border-b border-line">
      <header className="flex flex-wrap items-baseline gap-x-2 gap-y-0.5 bg-surface px-3 py-2">
        <h2 className="text-base font-medium">{term.name || 'Untitled term'}</h2>
        <p className="num text-tiny text-muted">
          {dayMonthLabel(term.start)} to {dayMonthLabel(term.end)}, {total} weeks
        </p>
        {current && week !== null ? (
          <span className="num rounded-full bg-accent px-2 py-0.5 text-micro font-medium text-[color:var(--accent-ink)]">
            week {week}
          </span>
        ) : null}
      </header>

      {series.length === 0 ? (
        <p className="px-3 pb-2 text-tiny text-faint">No courses in this term.</p>
      ) : (
        <ul>
          {series.map((s) => {
            const color = occurrenceColor(s.colorHex, s.kind)
            return (
              <li
                key={s.id}
                className="flex flex-wrap items-baseline gap-x-2.5 gap-y-0.5 border-t border-line px-3 py-2"
              >
                <ColorDot hex={color} size={7} />
                <span className="text-base font-medium">{s.title || 'Untitled'}</span>
                <span className="num text-sm text-muted">{scheduleSummary(s)}</span>
                <span className="text-tiny text-faint">{weeksSummary(s, total)}</span>
                {s.location ? (
                  <span className="inline-flex items-center gap-1 text-tiny text-faint">
                    <MapPinIcon size={11} />
                    {s.location}
                  </span>
                ) : null}
                <span className="ml-auto text-tiny" style={{ color: kindColor(s.kind) }}>
                  {kindName(s.kind)}
                </span>
              </li>
            )
          })}
        </ul>
      )}

      {blackouts.length > 0 ? (
        <div className="border-t border-line bg-bg px-3 py-2">
          <p className="text-tiny font-medium text-muted">Cleared periods</p>
          <ul className="mt-1 flex flex-col gap-0.5">
            {blackouts.map((b) => (
              <li key={b.id} className="flex flex-wrap items-baseline gap-x-2 text-sm text-muted">
                <span className="num">
                  {dayMonthLabel(b.start)} to {dayMonthLabel(b.end)}
                </span>
                <span className="text-tiny text-faint">
                  {b.kinds.length === 0
                    ? 'everything recurring'
                    : b.kinds.map(kindName).join(', ')}
                </span>
                {b.reason ? <span className="text-tiny text-faint">{b.reason}</span> : null}
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </section>
  )
}
