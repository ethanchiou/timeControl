import { useState, type ReactNode } from 'react'
import { NavLink } from 'react-router-dom'
import {
  CalendarBlankIcon,
  CheckSquareIcon,
  GraduationCapIcon,
  SquaresFourIcon,
  SunIcon,
  UsersThreeIcon,
} from '@phosphor-icons/react'
import { useAuth } from '@/data/auth'
import { useStore } from '@/data/store'
import { Button, ErrorNote, Field, Sheet, TextInput } from './primitives'

const NAV = [
  { to: '/today', label: 'Today', Icon: SunIcon },
  { to: '/week', label: 'Week', Icon: CalendarBlankIcon },
  { to: '/month', label: 'Month', Icon: SquaresFourIcon },
  { to: '/todos', label: 'Todos', Icon: CheckSquareIcon },
  { to: '/groups', label: 'Groups', Icon: UsersThreeIcon },
  { to: '/terms', label: 'Terms', Icon: GraduationCapIcon },
] as const

export function Shell({ children }: { children: ReactNode }) {
  const { displayName, email } = useAuth()
  const { error } = useStore()
  const [editingProfile, setEditingProfile] = useState(false)
  const name = displayName || email?.split('@')[0] || 'You'

  return (
    <div className="flex h-full flex-col lg:flex-row">
      {/* Desktop rail. On a phone the same destinations sit in the bottom bar. */}
      <nav className="hidden shrink-0 flex-col border-r border-line bg-surface lg:flex lg:w-rail">
        <div className="px-3 py-3">
          <p className="text-base font-semibold tracking-tight">TimeControl</p>
        </div>
        <div className="flex flex-1 flex-col gap-px px-1.5">
          {NAV.map(({ to, label, Icon }) => (
            <NavLink
              key={to}
              to={to}
              className={({ isActive }) =>
                `flex items-center gap-2.5 rounded px-2 py-1.5 text-base transition-colors duration-150 ${
                  isActive ? 'bg-sunken font-medium text-ink' : 'text-muted hover:bg-sunken hover:text-ink'
                }`
              }
            >
              <Icon size={16} />
              {label}
            </NavLink>
          ))}
        </div>
        <button
          type="button"
          onClick={() => setEditingProfile(true)}
          className="m-1.5 flex items-center gap-2 rounded px-2 py-1.5 text-left transition-colors duration-150 hover:bg-sunken"
        >
          <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-accent text-tiny font-semibold text-[color:var(--accent-ink)]">
            {name.slice(0, 1).toUpperCase()}
          </span>
          <span className="min-w-0 flex-1">
            <span className="block truncate text-sm">{name}</span>
            <span className="block truncate text-micro text-faint">Profile</span>
          </span>
        </button>
      </nav>

      {/* Phone top bar: the app name plus the same profile entry the rail has. */}
      <header className="flex shrink-0 items-center justify-between border-b border-line bg-surface px-3 py-2 lg:hidden">
        <p className="text-base font-semibold tracking-tight">TimeControl</p>
        <button
          type="button"
          onClick={() => setEditingProfile(true)}
          aria-label="Profile"
          className="flex h-6 w-6 items-center justify-center rounded-full bg-accent text-tiny font-semibold text-[color:var(--accent-ink)]"
        >
          {name.slice(0, 1).toUpperCase()}
        </button>
      </header>

      <main className="flex min-h-0 min-w-0 flex-1 flex-col">
        {error ? (
          <div className="px-3 pt-2">
            <ErrorNote>{error}</ErrorNote>
          </div>
        ) : null}
        {children}
      </main>

      <nav className="grid shrink-0 grid-cols-6 border-t border-line bg-surface pb-[env(safe-area-inset-bottom)] lg:hidden">
        {NAV.map(({ to, label, Icon }) => (
          <NavLink
            key={to}
            to={to}
            className={({ isActive }) =>
              `flex flex-col items-center gap-0.5 py-1.5 text-micro transition-colors duration-150 ${
                isActive ? 'text-accent' : 'text-muted'
              }`
            }
          >
            <Icon size={18} />
            {label}
          </NavLink>
        ))}
      </nav>

      {editingProfile ? <ProfileSheet onClose={() => setEditingProfile(false)} /> : null}
    </div>
  )
}

function ProfileSheet({ onClose }: { onClose: () => void }) {
  const { displayName, email, setDisplayName, signOut } = useAuth()
  const [name, setName] = useState(displayName)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function save() {
    setBusy(true)
    const { error: failure } = await setDisplayName(name)
    setBusy(false)
    if (failure) setError(failure)
    else onClose()
  }

  return (
    <Sheet
      title="Profile"
      onClose={onClose}
      onSubmit={save}
      footer={
        <>
          <Button tone="quiet" className="mr-auto" onClick={() => void signOut()}>
            Sign out
          </Button>
          <Button tone="quiet" onClick={onClose}>
            Cancel
          </Button>
          <Button tone="primary" onClick={save} disabled={busy}>
            Save
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-3">
        {error ? <ErrorNote>{error}</ErrorNote> : null}
        <Field label="Display name" hint="What the people in your groups see.">
          <TextInput value={name} onChange={(e) => setName(e.target.value)} autoFocus />
        </Field>
        <Field label="Email">
          <TextInput value={email ?? ''} readOnly disabled />
        </Field>
      </div>
    </Sheet>
  )
}
