import { useEffect, useId, useRef, type ReactNode } from 'react'
import { CheckIcon, XIcon } from '@phosphor-icons/react'
import { kindColor, kindName, type Kind } from '@/core'

/* Buttons -------------------------------------------------------------------------------------- */

type ButtonTone = 'primary' | 'default' | 'quiet' | 'danger'

const TONES: Record<ButtonTone, string> = {
  primary: 'bg-accent text-[color:var(--accent-ink)] border-transparent hover:brightness-110',
  default: 'bg-surface text-ink border-line hover:border-line-strong',
  quiet: 'bg-transparent text-muted border-transparent hover:bg-sunken hover:text-ink',
  danger: 'bg-transparent text-danger border-transparent hover:bg-sunken',
}

export function Button({
  tone = 'default',
  className = '',
  ...props
}: React.ButtonHTMLAttributes<HTMLButtonElement> & { tone?: ButtonTone }) {
  return (
    <button
      type="button"
      className={`inline-flex select-none items-center justify-center gap-1.5 whitespace-nowrap rounded border px-2.5 py-1.5 text-sm font-medium transition-[background-color,border-color,filter,transform] duration-150 active:translate-y-px disabled:pointer-events-none disabled:opacity-40 ${TONES[tone]} ${className}`}
      {...props}
    />
  )
}

export function IconButton({
  label,
  className = '',
  ...props
}: React.ButtonHTMLAttributes<HTMLButtonElement> & { label: string }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      className={`inline-flex h-7 w-7 items-center justify-center rounded border border-transparent text-muted transition-colors duration-150 hover:bg-sunken hover:text-ink active:translate-y-px ${className}`}
      {...props}
    />
  )
}

/* Form fields ---------------------------------------------------------------------------------- */

export function Field({
  label,
  hint,
  error,
  children,
}: {
  label: string
  hint?: string
  error?: string | null
  children: ReactNode
}) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="text-tiny font-medium text-muted">{label}</span>
      {children}
      {hint && !error ? <span className="text-tiny text-faint">{hint}</span> : null}
      {error ? <span className="text-tiny text-danger">{error}</span> : null}
    </label>
  )
}

const CONTROL =
  'w-full rounded border border-line bg-surface px-2 py-1.5 text-base text-ink placeholder:text-faint focus:border-accent focus:outline-none'

export function TextInput(props: React.InputHTMLAttributes<HTMLInputElement>) {
  const { className = '', ...rest } = props
  return <input className={`${CONTROL} ${className}`} {...rest} />
}

export function TextArea(props: React.TextareaHTMLAttributes<HTMLTextAreaElement>) {
  const { className = '', ...rest } = props
  return <textarea className={`${CONTROL} resize-y ${className}`} rows={3} {...rest} />
}

export function Select(props: React.SelectHTMLAttributes<HTMLSelectElement>) {
  const { className = '', ...rest } = props
  return <select className={`${CONTROL} ${className}`} {...rest} />
}

export function Switch({
  checked,
  onChange,
  label,
}: {
  checked: boolean
  onChange: (next: boolean) => void
  label: string
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      className="flex w-full items-center justify-between gap-3 rounded border border-line bg-surface px-2 py-1.5 text-left text-base transition-colors duration-150 hover:border-line-strong"
    >
      <span>{label}</span>
      <span
        className={`relative h-[18px] w-[30px] shrink-0 rounded-full transition-colors duration-150 ${checked ? 'bg-accent' : 'bg-line-strong'}`}
      >
        <span
          className={`absolute top-[2px] h-[14px] w-[14px] rounded-full bg-surface transition-[left] duration-150 ${checked ? 'left-[14px]' : 'left-[2px]'}`}
        />
      </span>
    </button>
  )
}

/* Badges --------------------------------------------------------------------------------------- */

export function KindBadge({ kind }: { kind: Kind }) {
  const tint = kindColor(kind)
  return (
    <span
      className="tinted inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-tiny font-medium"
      style={{ ['--tint' as string]: tint, color: tint }}
    >
      <span className="h-[5px] w-[5px] rounded-full" style={{ background: tint }} />
      {kindName(kind)}
    </span>
  )
}

export function ColorDot({ hex, size = 8 }: { hex: string; size?: number }) {
  return (
    <span
      className="inline-block shrink-0 rounded-full"
      style={{ background: hex, width: size, height: size }}
    />
  )
}

/* Colour picker ---------------------------------------------------------------------------------

   Matches the native app's palette. The leading swatch leaves the choice unset so the colour keeps
   following the kind when the kind changes later. */

export const PALETTE = [
  '#4F7CFF',
  '#A855F7',
  '#10B981',
  '#F59E0B',
  '#E5484D',
  '#06B6D4',
  '#EC4899',
  '#6B7280',
] as const

export function ColorSwatchRow({
  value,
  onChange,
  matching,
  matchColor,
  matchLabel = 'Match the kind',
}: {
  value: string | null
  onChange: (next: string | null) => void
  /** The kind to inherit from. Omit both this and matchColor for a picker with no inherited option. */
  matching?: Kind | null
  /** An explicit colour to inherit from, for things that follow something other than a kind. */
  matchColor?: string
  matchLabel?: string
}) {
  const inheritedColor = matchColor ?? (matching ? kindColor(matching) : null)
  return (
    <div className="flex flex-wrap gap-1.5">
      {inheritedColor ? (
        <Swatch
          hex={inheritedColor}
          selected={value === null}
          label={matchLabel}
          inherited
          onClick={() => onChange(null)}
        />
      ) : null}
      {PALETTE.map((hex) => (
        <Swatch
          key={hex}
          hex={hex}
          selected={value === hex}
          label={`Colour ${hex}`}
          onClick={() => onChange(hex)}
        />
      ))}
    </div>
  )
}

function Swatch({
  hex,
  selected,
  label,
  inherited = false,
  onClick,
}: {
  hex: string
  selected: boolean
  label: string
  inherited?: boolean
  onClick: () => void
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      title={label}
      aria-pressed={selected}
      className="flex h-6 w-6 items-center justify-center rounded-full transition-transform duration-150 active:scale-95"
      style={{
        background: hex,
        boxShadow: inherited ? `inset 0 0 0 2px color-mix(in oklab, ${hex} 60%, white)` : undefined,
      }}
    >
      {selected ? <CheckIcon size={12} weight="bold" color="#fff" /> : null}
    </button>
  )
}

/* Progress ring ---------------------------------------------------------------------------------- */

export function Ring({
  done,
  total,
  size = 34,
}: {
  done: number
  total: number
  size?: number
}) {
  const stroke = 3
  const radius = (size - stroke) / 2
  const circumference = 2 * Math.PI * radius
  const value = total === 0 ? 0 : done / total
  return (
    <div
      className="relative shrink-0"
      style={{ width: size, height: size }}
      role="img"
      aria-label={total === 0 ? 'Nothing due' : `${done} of ${total} done`}
    >
      <svg width={size} height={size} className="-rotate-90">
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke="var(--line)"
          strokeWidth={stroke}
        />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke={value >= 1 ? '#10B981' : 'var(--accent)'}
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={circumference * (1 - value)}
          className="transition-[stroke-dashoffset] duration-300"
        />
      </svg>
      <span className="num absolute inset-0 flex items-center justify-center text-micro text-muted">
        {total === 0 ? '' : `${done}/${total}`}
      </span>
    </div>
  )
}

/* Sheet ------------------------------------------------------------------------------------------

   Escape closes. Enter saves, except inside a textarea where it is a newline. */

export function Sheet({
  title,
  onClose,
  onSubmit,
  footer,
  children,
  wide = false,
}: {
  title: string
  onClose: () => void
  onSubmit?: () => void
  footer?: ReactNode
  children: ReactNode
  wide?: boolean
}) {
  const panel = useRef<HTMLDivElement>(null)
  const headingId = useId()

  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null
    const first = panel.current?.querySelector<HTMLElement>(
      'input, select, textarea, button:not([aria-label="Close"])',
    )
    first?.focus()
    return () => previous?.focus()
  }, [])

  function handleKeyDown(event: React.KeyboardEvent) {
    if (event.key === 'Escape') {
      event.stopPropagation()
      onClose()
      return
    }
    if (event.key === 'Enter' && onSubmit) {
      const target = event.target as HTMLElement
      if (target.tagName === 'TEXTAREA' || target.tagName === 'BUTTON') return
      event.preventDefault()
      onSubmit()
    }
  }

  return (
    <div
      className="fixed inset-0 z-40 flex items-end justify-center bg-black/35 p-0 sm:items-center sm:p-6"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose()
      }}
    >
      <div
        ref={panel}
        role="dialog"
        aria-modal="true"
        aria-labelledby={headingId}
        onKeyDown={handleKeyDown}
        className={`flex max-h-[92dvh] w-full flex-col rounded-t border border-line bg-surface shadow-[0_16px_48px_-12px_rgba(20,20,30,0.35)] sm:rounded ${wide ? 'sm:max-w-2xl' : 'sm:max-w-md'}`}
      >
        <header className="flex shrink-0 items-center justify-between border-b border-line px-3 py-2">
          <h2 id={headingId} className="text-base font-semibold">
            {title}
          </h2>
          <IconButton label="Close" onClick={onClose}>
            <XIcon size={15} />
          </IconButton>
        </header>
        <div className="flex-1 overflow-y-auto px-3 py-3">{children}</div>
        {footer ? (
          <footer className="flex shrink-0 items-center justify-end gap-2 border-t border-line px-3 py-2">
            {footer}
          </footer>
        ) : null}
      </div>
    </div>
  )
}

/* States ------------------------------------------------------------------------------------------ */

export function EmptyState({ title, hint }: { title: string; hint?: string }) {
  return (
    <div className="flex flex-col items-center justify-center gap-1 px-6 py-12 text-center">
      <p className="text-base text-muted">{title}</p>
      {hint ? <p className="text-sm text-faint">{hint}</p> : null}
    </div>
  )
}

export function ErrorNote({ children }: { children: ReactNode }) {
  return (
    <p role="alert" className="rounded bg-danger/10 px-2 py-1.5 text-sm text-danger">
      {children}
    </p>
  )
}

/** Skeletons take the shape of the rows they stand in for, so nothing jumps when data lands. */
export function SkeletonRows({ count = 5 }: { count?: number }) {
  return (
    <div className="flex flex-col gap-px" aria-hidden>
      {Array.from({ length: count }, (_, i) => (
        <div key={i} className="flex items-center gap-3 px-3 py-2.5">
          <div className="skeleton h-3 w-12 rounded" />
          <div className="skeleton h-3 flex-1 rounded" style={{ maxWidth: `${40 + ((i * 17) % 45)}%` }} />
        </div>
      ))}
    </div>
  )
}
