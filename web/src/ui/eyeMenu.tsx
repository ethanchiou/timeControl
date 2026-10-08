import { useEffect, useRef, useState } from 'react'
import {
  CheckIcon,
  DotsThreeIcon,
  EyeIcon,
  EyeSlashIcon,
  MinusIcon,
} from '@phosphor-icons/react'
import type { EyeFilter } from '@/core'
import { useStore } from '@/data/store'

/**
 * The eye. Independent flags, and it says how many items it is currently hiding so the count is
 * never a mystery. The group flag hides every group at once; its three dots open a list to hide
 * groups one by one.
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
  const [groupsOpen, setGroupsOpen] = useState(false)
  const wrapper = useRef<HTMLDivElement>(null)
  const { data } = useStore()
  const groups = data.groups

  const hiddenIds = filter.hiddenGroupIds ?? []
  const isGroupHidden = (id: string) => filter.hideGroup || hiddenIds.includes(id)
  const hiddenGroupCount = groups.filter((g) => isGroupHidden(g.id)).length
  const allGroupsHidden =
    filter.hideGroup || (groups.length > 0 && hiddenGroupCount === groups.length)
  const someGroupsHidden = !allGroupsHidden && hiddenGroupCount > 0
  const on = filter.hideRoutine || allGroupsHidden || someGroupsHidden

  function setAllGroups(hidden: boolean) {
    onChange({ ...filter, hideGroup: hidden, hiddenGroupIds: [] })
  }

  function toggleGroup(id: string) {
    // Hiding all at once also covers groups joined later; unticking one spells the rest out.
    const current = filter.hideGroup ? groups.map((g) => g.id) : hiddenIds
    const next = current.includes(id) ? current.filter((g) => g !== id) : [...current, id]
    onChange({ ...filter, hideGroup: false, hiddenGroupIds: next })
  }

  useEffect(() => {
    if (!open) {
      setGroupsOpen(false)
      return
    }
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
          className="absolute right-0 z-30 mt-1 w-64 rounded border border-line bg-surface p-1 shadow-[0_10px_30px_-10px_rgba(20,20,30,0.35)]"
        >
          <MenuToggle
            checked={filter.hideRoutine}
            onChange={(v) => onChange({ ...filter, hideRoutine: v })}
            title="Hide routine"
            hint="Courses and events you marked routine"
          />
          <div className="flex items-start">
            <MenuToggle
              checked={allGroupsHidden}
              mixed={someGroupsHidden}
              onChange={() => setAllGroups(!allGroupsHidden)}
              title="Hide group items"
              hint={
                someGroupsHidden
                  ? `${hiddenGroupCount} of ${groups.length} groups hidden`
                  : 'Everything shared through a group'
              }
            />
            {groups.length > 0 ? (
              <button
                type="button"
                onClick={() => setGroupsOpen((v) => !v)}
                aria-expanded={groupsOpen}
                aria-label="Choose groups to hide"
                title="Choose groups to hide"
                className={`mt-0.5 inline-flex h-7 w-7 shrink-0 items-center justify-center rounded text-muted transition-colors duration-150 hover:bg-sunken hover:text-ink ${
                  groupsOpen ? 'bg-sunken text-ink' : ''
                }`}
              >
                <DotsThreeIcon size={16} weight="bold" />
              </button>
            ) : null}
          </div>
          {groupsOpen ? (
            <div role="group" aria-label="Groups" className="ml-5 border-l border-line pl-1">
              {groups.map((g) => (
                <MenuToggle
                  key={g.id}
                  checked={isGroupHidden(g.id)}
                  onChange={() => toggleGroup(g.id)}
                  title={g.name}
                  swatch={g.resolvedColorHex}
                />
              ))}
            </div>
          ) : null}
        </div>
      ) : null}
    </div>
  )
}

function MenuToggle({
  checked,
  mixed = false,
  onChange,
  title,
  hint,
  swatch,
}: {
  checked: boolean
  /** Some but not all of what this box covers is ticked. */
  mixed?: boolean
  onChange: (next: boolean) => void
  title: string
  hint?: string
  swatch?: string
}) {
  const filled = checked || mixed
  return (
    <button
      type="button"
      role="menuitemcheckbox"
      aria-checked={mixed ? 'mixed' : checked}
      onClick={() => onChange(!checked)}
      className="flex min-w-0 flex-1 items-start gap-2 rounded px-2 py-1.5 text-left hover:bg-sunken"
    >
      <span
        className={`mt-[3px] flex h-3.5 w-3.5 shrink-0 items-center justify-center rounded-[3px] border ${
          filled ? 'border-accent bg-accent' : 'border-line-strong'
        }`}
      >
        {checked ? (
          <CheckIcon size={10} weight="bold" color="var(--accent-ink)" />
        ) : mixed ? (
          <MinusIcon size={10} weight="bold" color="var(--accent-ink)" />
        ) : null}
      </span>
      {swatch ? (
        <span
          aria-hidden
          className="mt-[5px] h-2.5 w-2.5 shrink-0 rounded-full"
          style={{ backgroundColor: swatch }}
        />
      ) : null}
      <span className="flex min-w-0 flex-col">
        <span className="truncate text-sm">{title}</span>
        {hint ? <span className="text-tiny text-faint">{hint}</span> : null}
      </span>
    </button>
  )
}
