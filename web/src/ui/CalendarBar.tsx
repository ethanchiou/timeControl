import { CaretLeftIcon, CaretRightIcon, PlusIcon } from '@phosphor-icons/react'
import type { EyeFilter } from '@/core'
import { EyeMenu } from './eyeMenu'
import { Button, IconButton } from './primitives'

/** The one strip every calendar scale shares: where you are, how to move, and what to hide. */
export function CalendarBar({
  title,
  subtitle,
  onPrev,
  onNext,
  onToday,
  atToday,
  filter,
  onFilterChange,
  hiddenCount,
  onAdd,
  addLabel = 'New event',
}: {
  title: string
  subtitle?: string
  onPrev: () => void
  onNext: () => void
  onToday: () => void
  atToday: boolean
  filter: EyeFilter
  onFilterChange: (next: EyeFilter) => void
  hiddenCount: number
  onAdd: () => void
  addLabel?: string
}) {
  return (
    <header className="flex shrink-0 flex-wrap items-center gap-x-2 gap-y-1.5 border-b border-line bg-surface px-3 py-2">
      <div className="mr-auto flex min-w-0 items-baseline gap-2">
        <h1 className="truncate text-lg font-semibold tracking-tight">{title}</h1>
        {subtitle ? <p className="truncate text-tiny text-muted">{subtitle}</p> : null}
      </div>
      <div className="flex items-center gap-1">
        <IconButton label="Previous" onClick={onPrev}>
          <CaretLeftIcon size={14} weight="bold" />
        </IconButton>
        <button
          type="button"
          onClick={onToday}
          disabled={atToday}
          className="rounded border border-line px-2 py-1 text-tiny text-muted transition-colors duration-150 hover:border-line-strong hover:text-ink disabled:pointer-events-none disabled:opacity-40"
        >
          Today
        </button>
        <IconButton label="Next" onClick={onNext}>
          <CaretRightIcon size={14} weight="bold" />
        </IconButton>
      </div>
      <EyeMenu filter={filter} onChange={onFilterChange} hiddenCount={hiddenCount} />
      <Button tone="primary" onClick={onAdd} className="h-7 px-2 text-tiny">
        <PlusIcon size={13} weight="bold" />
        <span className="hidden sm:inline">{addLabel}</span>
      </Button>
    </header>
  )
}
