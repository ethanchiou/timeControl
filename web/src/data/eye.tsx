import { createContext, useCallback, useContext, useMemo, useState } from 'react'
import type { EyeFilter } from '@/core'

export type Scale = 'day' | 'week' | 'month'

/**
 * The eye's two flags, remembered per scale.
 *
 * A month is mostly the timetable repeating, so it opens with both hidden and shows only the
 * one-time things. A day and a week have the room for everything, so they open unfiltered.
 */
const DEFAULTS: Record<Scale, EyeFilter> = {
  day: { hideRoutine: false, hideGroup: false },
  week: { hideRoutine: false, hideGroup: false },
  month: { hideRoutine: true, hideGroup: true },
}

interface EyeValue {
  filterFor: (scale: Scale) => EyeFilter
  setFilter: (scale: Scale, filter: EyeFilter) => void
}

const EyeContext = createContext<EyeValue | null>(null)

export function EyeProvider({ children }: { children: React.ReactNode }) {
  const [filters, setFilters] = useState<Record<Scale, EyeFilter>>(DEFAULTS)

  const filterFor = useCallback((scale: Scale) => filters[scale], [filters])
  const setFilter = useCallback((scale: Scale, filter: EyeFilter) => {
    setFilters((prev) => ({ ...prev, [scale]: filter }))
  }, [])

  const value = useMemo(() => ({ filterFor, setFilter }), [filterFor, setFilter])
  return <EyeContext.Provider value={value}>{children}</EyeContext.Provider>
}

export function useEye(scale: Scale): [EyeFilter, (filter: EyeFilter) => void] {
  const context = useContext(EyeContext)
  if (!context) throw new Error('useEye must be used inside EyeProvider')
  const filter = context.filterFor(scale)
  const set = useCallback((next: EyeFilter) => context.setFilter(scale, next), [context, scale])
  return [filter, set]
}
