import { MapPinIcon, UsersThreeIcon } from '@phosphor-icons/react'
import { kindName, type Occurrence } from '@/core'
import { hourLabel, timeRange, timeRangeCompact } from '@/lib/format'
import { KindBadge } from './primitives'

/** The small people mark that says "this came from a group", used wherever a group item shows. */
export function GroupMark({ size = 12 }: { size?: number }) {
  return <UsersThreeIcon size={size} weight="fill" aria-label="Group" />
}

export function GroupChip({ name, color }: { name: string; color: string }) {
  return (
    <span
      className="tinted-strong inline-flex max-w-full items-center gap-1 rounded-full px-1.5 py-px text-micro font-medium"
      style={{ ['--tint' as string]: color, color }}
    >
      <GroupMark size={10} />
      <span className="truncate">{name}</span>
    </span>
  )
}

function describe(o: Occurrence): string {
  const where = o.location ? `, ${o.location}` : ''
  const who = o.group ? `, ${o.group.name}` : ''
  return o.isAllDay
    ? `${o.title}, all day${where}${who}`
    : `${o.title}, ${timeRange(o.start, o.end)}${where}${who}`
}

/**
 * One occurrence drawn inside a day column. The caller sizes it; the contents thin out as the
 * height shrinks, the same way the native block does.
 */
export function OccurrenceBlock({
  occurrence,
  height,
  onOpen,
}: {
  occurrence: Occurrence
  height: number
  onOpen: () => void
}) {
  const tint = occurrence.colorHex
  return (
    <button
      type="button"
      onClick={onOpen}
      title={describe(occurrence)}
      className="tinted group flex h-full w-full overflow-hidden rounded text-left transition-[filter] duration-150 hover:brightness-[0.97] active:translate-y-px"
      style={{ ['--tint' as string]: tint }}
    >
      <span className="w-[3px] shrink-0" style={{ background: tint }} />
      <span className="flex min-w-0 flex-col gap-px px-1.5 py-1">
        <span className="flex items-center gap-1">
          {occurrence.group ? (
            <span style={{ color: tint }} className="shrink-0">
              <GroupMark size={10} />
            </span>
          ) : null}
          <span
            className="truncate text-tiny font-semibold leading-4"
            style={{ display: '-webkit-box', WebkitBoxOrient: 'vertical', WebkitLineClamp: height > 42 ? 2 : 1, whiteSpace: 'normal', overflow: 'hidden' }}
          >
            {occurrence.title}
          </span>
        </span>
        {!occurrence.isAllDay && height > 42 ? (
          <span className="num truncate text-micro text-muted">
            {timeRangeCompact(occurrence.start, occurrence.end)}
          </span>
        ) : null}
        {height > 64 && occurrence.group ? (
          <span className="truncate text-micro" style={{ color: tint }}>
            {occurrence.group.name}
          </span>
        ) : null}
        {height > 64 && !occurrence.group && occurrence.location ? (
          <span className="truncate text-micro text-muted">{occurrence.location}</span>
        ) : null}
      </span>
    </button>
  )
}

/** A row in a day's agenda: time on the left, the item on the right. */
export function OccurrenceRow({
  occurrence,
  onOpen,
}: {
  occurrence: Occurrence
  onOpen: () => void
}) {
  const tint = occurrence.colorHex
  return (
    <button
      type="button"
      onClick={onOpen}
      className="flex w-full items-start gap-3 border-b border-line px-3 py-2 text-left transition-colors duration-150 hover:bg-sunken"
    >
      <span className="num w-[52px] shrink-0 pt-px text-right text-tiny text-muted">
        {occurrence.isAllDay ? 'all day' : timeRangeCompact(occurrence.start, occurrence.end).split('-')[0]}
      </span>
      <span className="w-[3px] shrink-0 self-stretch rounded-full" style={{ background: tint }} />
      <span className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="flex items-center gap-1.5">
          <span className="truncate text-base font-medium">{occurrence.title}</span>
          {occurrence.group ? <GroupChip name={occurrence.group.name} color={tint} /> : null}
        </span>
        <span className="flex flex-wrap items-center gap-x-2 gap-y-0.5 text-tiny text-muted">
          {!occurrence.isAllDay ? (
            <span className="num">{timeRange(occurrence.start, occurrence.end)}</span>
          ) : null}
          {occurrence.location ? (
            <span className="inline-flex items-center gap-1">
              <MapPinIcon size={11} />
              {occurrence.location}
            </span>
          ) : null}
          <span>{kindName(occurrence.kind)}</span>
        </span>
      </span>
    </button>
  )
}

/** An all-day item, drawn as a pill above the timed rows. */
export function AllDayPill({
  occurrence,
  onOpen,
}: {
  occurrence: Occurrence
  onOpen: () => void
}) {
  const tint = occurrence.colorHex
  return (
    <button
      type="button"
      onClick={onOpen}
      title={describe(occurrence)}
      className="tinted flex max-w-full items-center gap-1.5 rounded-full px-2 py-0.5 text-tiny font-medium transition-[filter] duration-150 hover:brightness-[0.97] active:translate-y-px"
      style={{ ['--tint' as string]: tint }}
    >
      {occurrence.group ? (
        <span style={{ color: tint }}>
          <GroupMark size={10} />
        </span>
      ) : (
        <span className="h-[5px] w-[5px] shrink-0 rounded-full" style={{ background: tint }} />
      )}
      <span className="truncate">{occurrence.title}</span>
    </button>
  )
}

/** A single line in a month cell. */
export function MonthPill({
  occurrence,
  onOpen,
}: {
  occurrence: Occurrence
  onOpen: () => void
}) {
  const tint = occurrence.colorHex
  return (
    <button
      type="button"
      onClick={onOpen}
      title={describe(occurrence)}
      className="flex w-full items-center gap-1 rounded px-1 py-px text-left text-micro transition-colors duration-150 hover:bg-sunken"
    >
      {occurrence.group ? (
        <span style={{ color: tint }} className="shrink-0">
          <GroupMark size={9} />
        </span>
      ) : (
        <span className="h-[5px] w-[5px] shrink-0 rounded-full" style={{ background: tint }} />
      )}
      {!occurrence.isAllDay ? (
        <span className="num shrink-0 whitespace-nowrap text-faint">
          {hourLabel(occurrence.start.getHours())}
        </span>
      ) : null}
      <span className="truncate">{occurrence.title}</span>
    </button>
  )
}

/** The details card behind a tap on any occurrence. */
export function OccurrenceDetails({ occurrence }: { occurrence: Occurrence }) {
  return (
    <div className="flex flex-col gap-2.5">
      <div className="flex flex-wrap items-center gap-1.5">
        <KindBadge kind={occurrence.kind} />
        {occurrence.group ? (
          <GroupChip name={occurrence.group.name} color={occurrence.colorHex} />
        ) : null}
        {occurrence.isRoutine ? (
          <span className="rounded-full bg-sunken px-2 py-0.5 text-tiny text-muted">Routine</span>
        ) : null}
      </div>
      <p className="text-lg font-semibold">{occurrence.title}</p>
      <p className="num text-sm text-muted">
        {occurrence.isAllDay ? 'All day' : timeRange(occurrence.start, occurrence.end)}
      </p>
      {occurrence.location ? (
        <p className="inline-flex items-center gap-1.5 text-sm text-muted">
          <MapPinIcon size={13} />
          {occurrence.location}
        </p>
      ) : null}
      {occurrence.group && occurrence.authorName ? (
        <p className="text-sm text-muted">Added by {occurrence.authorName}</p>
      ) : null}
      {occurrence.notes ? (
        <p className="whitespace-pre-wrap text-sm text-muted">{occurrence.notes}</p>
      ) : null}
    </div>
  )
}
