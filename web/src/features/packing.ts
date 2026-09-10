import { minuteOfDay, type Occurrence } from '@/core'

export interface PackedOccurrence {
  occurrence: Occurrence
  /** Fractions of the column width. */
  left: number
  width: number
  topMinute: number
  endMinute: number
}

/**
 * Column packing for overlapping occurrences in one day.
 *
 * Items that overlap form a cluster; every item in a cluster takes the first free column, and the
 * cluster is divided by however many columns it needed. Simple, stable, and good enough for a
 * timetable, which rarely stacks more than three deep.
 */
export function packDay(occurrences: readonly Occurrence[]): PackedOccurrence[] {
  const timed = occurrences
    .filter((o) => !o.isAllDay)
    .map((o) => {
      const start = minuteOfDay(o.start)
      // A zero-length item still needs a strip you can hit.
      const end = Math.max(minuteOfDay(o.end), start + 15)
      return { occurrence: o, topMinute: start, endMinute: end }
    })
    .sort((a, b) => a.topMinute - b.topMinute || b.endMinute - a.endMinute)

  const packed: PackedOccurrence[] = []
  let cluster: Array<(typeof timed)[number]> = []
  let columns: number[] = []
  let assignments: number[] = []

  function flush() {
    if (cluster.length === 0) return
    const width = 1 / columns.length
    cluster.forEach((item, i) => {
      packed.push({ ...item, left: assignments[i]! * width, width })
    })
    cluster = []
    columns = []
    assignments = []
  }

  for (const item of timed) {
    const clusterEnd = columns.length === 0 ? -1 : Math.max(...columns)
    if (item.topMinute >= clusterEnd) flush()

    let column = columns.findIndex((end) => end <= item.topMinute)
    if (column === -1) {
      columns.push(item.endMinute)
      column = columns.length - 1
    } else {
      columns[column] = item.endMinute
    }
    cluster.push(item)
    assignments.push(column)
  }
  flush()

  return packed
}
