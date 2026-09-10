import { useEffect, useRef, useState } from 'react'
import { dayKeyOf, minuteOfDay, type DayKey, type Occurrence } from '@/core'
import { hourLabel } from '@/lib/format'
import { OccurrenceBlock } from '@/ui/occurrence'
import { packDay } from './packing'

export const HOUR_HEIGHT = 46
const GUTTER = 52

/** The hour rules and the left-hand time gutter that every timed column sits on. */
export function HourGutter() {
  return (
    <div className="relative shrink-0" style={{ width: GUTTER }}>
      {Array.from({ length: 24 }, (_, hour) => (
        <div key={hour} className="relative" style={{ height: HOUR_HEIGHT }}>
          {hour > 0 ? (
            <span className="num absolute -top-[7px] right-1.5 whitespace-nowrap text-micro text-faint">
              {hourLabel(hour)}
            </span>
          ) : null}
        </div>
      ))}
    </div>
  )
}

/** One day's worth of timed blocks, positioned by their minutes. */
export function DayColumn({
  day,
  occurrences,
  onOpen,
  showNowLine,
}: {
  day: DayKey
  occurrences: readonly Occurrence[]
  onOpen: (occurrence: Occurrence) => void
  showNowLine: boolean
}) {
  const packed = packDay(occurrences)
  return (
    <div className="relative flex-1" style={{ height: 24 * HOUR_HEIGHT }} data-day={day}>
      {Array.from({ length: 24 }, (_, hour) => (
        <div
          key={hour}
          className="border-t border-line"
          style={{ height: HOUR_HEIGHT }}
          aria-hidden
        />
      ))}
      {packed.map(({ occurrence, left, width, topMinute, endMinute }) => {
        const height = ((endMinute - topMinute) / 60) * HOUR_HEIGHT
        return (
          <div
            key={occurrence.id}
            className="absolute px-px"
            style={{
              top: (topMinute / 60) * HOUR_HEIGHT,
              height: Math.max(height, 16),
              left: `${left * 100}%`,
              width: `${width * 100}%`,
            }}
          >
            <OccurrenceBlock
              occurrence={occurrence}
              height={height}
              onOpen={() => onOpen(occurrence)}
            />
          </div>
        )
      })}
      {showNowLine ? <NowLine /> : null}
    </div>
  )
}

function NowLine() {
  const [minute, setMinute] = useState(() => minuteOfDay(new Date()))
  useEffect(() => {
    const id = window.setInterval(() => setMinute(minuteOfDay(new Date())), 60_000)
    return () => window.clearInterval(id)
  }, [])
  return (
    <div
      className="pointer-events-none absolute inset-x-0 z-10 flex items-center"
      style={{ top: (minute / 60) * HOUR_HEIGHT }}
      aria-hidden
    >
      <span className="h-[7px] w-[7px] -translate-x-[3px] rounded-full bg-danger" />
      <span className="h-px flex-1 bg-danger" />
    </div>
  )
}

/**
 * Scrolls the grid so the day's first item is in view on open, or the working morning when the day
 * is empty. Without it every view opens on an empty midnight.
 */
export function useScrollToFirst(occurrences: readonly Occurrence[], ready: boolean) {
  const ref = useRef<HTMLDivElement>(null)
  const done = useRef(false)
  useEffect(() => {
    if (!ready || done.current || !ref.current) return
    const timed = occurrences.filter((o) => !o.isAllDay)
    const earliest = timed.length
      ? Math.min(...timed.map((o) => minuteOfDay(o.start)))
      : 8 * 60
    ref.current.scrollTop = Math.max(0, ((earliest - 30) / 60) * HOUR_HEIGHT)
    done.current = true
  }, [occurrences, ready])
  return ref
}

export function isToday(day: DayKey): boolean {
  return day === dayKeyOf(new Date())
}
