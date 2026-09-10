import { useEffect, useRef, useState } from 'react'
import { CheckIcon, EyeIcon, EyeSlashIcon } from '@phosphor-icons/react'
import type { EyeFilter } from '@/core'

/**
 * The eye. Two independent flags, and it says how many items it is currently hiding so the count
 * is never a mystery.
 */
export function EyeMenu({
  filter,
  onChange,
  hiddenCount,
}: {
  filter: EyeFilter
  onChange: (next: EyeFilter) => void
  hiddenCount: number
}) {
  const [open, setOpen] = useState(false)
  const wrapper = useRef<HTMLDivElement>(null)
  const on = filter.hideRoutine || filter.hideGroup

  useEffect(() => {
    if (!open) return
    function onPointerDown(event: MouseEvent) {
      if (!wrapper.current?.contains(event.target as Node)) setOpen(false)
    }
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') setOpen(false)
    }
    document.addEventListener('mousedown', onPointerDown)
    document.addEventListener('keydown', onKeyDown)
    return () => {
      document.removeEventListener('mousedown', onPointerDown)
      document.removeEventListener('keydown', onKeyDown)
    }
  }, [open])

  const label = on
    ? `Filtering, ${hiddenCount} hidden`
    : 'Show everything. Choose what to hide'

  return (
    <div className="relative" ref={wrapper}>
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        aria-haspopup="true"
        title={label}
        aria-label={label}
        className={`inline-flex h-7 items-center gap-1.5 rounded border px-2 text-tiny font-medium transition-colors duration-150 active:translate-y-px ${
          on
            ? 'border-transparent bg-accent text-[color:var(--accent-ink)]'
            : 'border-line bg-surface text-muted hover:border-line-strong hover:text-ink'
        }`}
      >
        {on ? <EyeSlashIcon size={14} /> : <EyeIcon size={14} />}
        {on && hiddenCount > 0 ? <span className="num">{hiddenCount} hidden</span> : null}
      </button>

      {open ? (
        <div
          role="menu"
          className="absolute right-0 z-30 mt-1 w-56 rounded border border-line bg-surface p-1 shadow-[0_10px_30px_-10px_rgba(20,20,30,0.35)]"
        >
          <MenuToggle
            checked={filter.hideRoutine}
            onChange={(v) => onChange({ ...filter, hideRoutine: v })}
            title="Hide routine"
            hint="Courses and events you marked routine"
          />
          <MenuToggle
            checked={filter.hideGroup}
            onChange={(v) => onChange({ ...filter, hideGroup: v })}
            title="Hide group items"
            hint="Everything shared through a group"
          />
        </div>
      ) : null}
    </div>
  )
}

function MenuToggle({
  checked,
  onChange,
  title,
  hint,
}: {
  checked: boolean
  onChange: (next: boolean) => void
  title: string
  hint: string
}) {
  return (
    <button
      type="button"
      role="menuitemcheckbox"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      className="flex w-full items-start gap-2 rounded px-2 py-1.5 text-left hover:bg-sunken"
    >
      <span
        className={`mt-[3px] flex h-3.5 w-3.5 shrink-0 items-center justify-center rounded-[3px] border ${
          checked ? 'border-accent bg-accent' : 'border-line-strong'
        }`}
      >
        {checked ? <CheckIcon size={10} weight="bold" color="var(--accent-ink)" /> : null}
      </span>
      <span className="flex flex-col">
        <span className="text-sm">{title}</span>
        <span className="text-tiny text-faint">{hint}</span>
      </span>
    </button>
  )
}
