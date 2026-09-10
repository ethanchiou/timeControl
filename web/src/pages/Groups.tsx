import { useState } from 'react'
import { CheckIcon, CopyIcon, PlusIcon, SignOutIcon } from '@phosphor-icons/react'
import { friendlyError } from '@/lib/supabase'
import { useAuth } from '@/data/auth'
import { useStore, type GroupSummary } from '@/data/store'
import {
  Button,
  ColorDot,
  ColorSwatchRow,
  EmptyState,
  ErrorNote,
  Field,
  PALETTE,
  Sheet,
  SkeletonRows,
  TextInput,
} from '@/ui/primitives'

/** The cap the server enforces on every membership insert. */
const GROUP_CAP = 5

export function Groups() {
  const { data, loading } = useStore()
  const [creating, setCreating] = useState(false)
  const [joining, setJoining] = useState(false)

  const atCap = data.groups.length >= GROUP_CAP

  return (
    <>
      <header className="flex shrink-0 flex-wrap items-center gap-2 border-b border-line bg-surface px-3 py-2">
        <h1 className="mr-auto text-lg font-semibold tracking-tight">Groups</h1>
        <span className="num text-tiny text-muted">
          {data.groups.length} of {GROUP_CAP}
        </span>
        <Button onClick={() => setJoining(true)} className="h-7 px-2 text-tiny" disabled={atCap}>
          Join with a code
        </Button>
        <Button
          tone="primary"
          onClick={() => setCreating(true)}
          className="h-7 px-2 text-tiny"
          disabled={atCap}
        >
          <PlusIcon size={13} weight="bold" />
          New group
        </Button>
      </header>

      <div className="min-h-0 flex-1 overflow-y-auto">
        {atCap ? (
          <p className="border-b border-line px-3 py-2 text-tiny text-muted">
            You are in five groups, which is the limit. Leave one to make room.
          </p>
        ) : null}

        {loading ? (
          <SkeletonRows count={3} />
        ) : data.groups.length === 0 ? (
          <EmptyState
            title="No groups yet"
            hint="Make one and share its code, or join with a code someone sent you."
          />
        ) : (
          data.groups.map((group) => <GroupCard key={group.id} group={group} />)
        )}
      </div>

      {creating ? <CreateGroupSheet onClose={() => setCreating(false)} /> : null}
      {joining ? <JoinGroupSheet onClose={() => setJoining(false)} /> : null}
    </>
  )
}

function GroupCard({ group }: { group: GroupSummary }) {
  const { userId } = useAuth()
  const { leaveGroup, setGroupColorOverride } = useStore()
  const [copied, setCopied] = useState(false)
  const [confirmingLeave, setConfirmingLeave] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function copyCode() {
    try {
      await navigator.clipboard.writeText(group.joinCode)
      setCopied(true)
      window.setTimeout(() => setCopied(false), 1600)
    } catch {
      setError('Could not reach the clipboard. Select the code and copy it by hand.')
    }
  }

  async function leave() {
    const { error: failure } = await leaveGroup(group.id)
    if (failure) setError(friendlyError(failure))
  }

  return (
    <section className="border-b border-line px-3 py-3">
      <div className="flex flex-wrap items-center gap-2">
        <ColorDot hex={group.resolvedColorHex} size={11} />
        <h2 className="mr-auto text-base font-medium">{group.name}</h2>
        <span className="text-tiny text-muted">
          {group.members.length} {group.members.length === 1 ? 'member' : 'members'}
        </span>
        <span className="rounded-full bg-sunken px-2 py-0.5 text-micro text-muted">
          {group.myRole === 'owner' ? 'You made it' : 'Member'}
        </span>
      </div>

      {error ? (
        <div className="mt-2">
          <ErrorNote>{error}</ErrorNote>
        </div>
      ) : null}

      <div className="mt-2.5 grid gap-3 sm:grid-cols-2">
        <div className="flex flex-col gap-1.5">
          <p className="text-tiny font-medium text-muted">Join code</p>
          <div className="flex items-center gap-1.5">
            <code className="num rounded border border-line bg-sunken px-2 py-1 text-base tracking-[0.18em]">
              {group.joinCode}
            </code>
            <button
              type="button"
              onClick={copyCode}
              aria-label="Copy join code"
              title="Copy join code"
              className="flex h-7 w-7 items-center justify-center rounded border border-line text-muted hover:border-line-strong hover:text-ink"
            >
              {copied ? <CheckIcon size={13} weight="bold" /> : <CopyIcon size={13} />}
            </button>
            {copied ? <span className="text-tiny text-muted">Copied</span> : null}
          </div>
        </div>

        <div className="flex flex-col gap-1.5">
          <p className="text-tiny font-medium text-muted">Your colour for this group</p>
          <ColorSwatchRow
            value={group.myColorOverride}
            onChange={(hex) => void setGroupColorOverride(group.id, hex)}
            matchColor={group.colorHex}
            matchLabel="Use the group colour"
          />
          <p className="text-tiny text-faint">Only you see this. It does not change the group.</p>
        </div>
      </div>

      <ul className="mt-3 flex flex-col">
        {group.members.map((member) => (
          <li
            key={member.userId}
            className="flex items-center gap-2 border-t border-line py-1.5 text-sm"
          >
            <ColorDot
              hex={member.colorOverrideHex ?? group.colorHex}
              size={7}
            />
            <span className="mr-auto truncate">
              {member.displayName}
              {member.userId === userId ? ' (you)' : ''}
            </span>
            <span className="text-tiny text-faint">{member.role}</span>
          </li>
        ))}
      </ul>

      <div className="mt-2.5 flex items-center gap-2">
        {confirmingLeave ? (
          <>
            <span className="text-tiny text-muted">
              Leave {group.name}? Its events drop off your calendar.
            </span>
            <Button tone="danger" onClick={leave}>
              Leave
            </Button>
            <Button tone="quiet" onClick={() => setConfirmingLeave(false)}>
              Stay
            </Button>
          </>
        ) : (
          <Button tone="quiet" onClick={() => setConfirmingLeave(true)}>
            <SignOutIcon size={13} />
            Leave group
          </Button>
        )}
      </div>
    </section>
  )
}

function CreateGroupSheet({ onClose }: { onClose: () => void }) {
  const { createGroup } = useStore()
  const [name, setName] = useState('')
  const [color, setColor] = useState<string>(PALETTE[0])
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function submit() {
    if (!name.trim() || busy) return
    setBusy(true)
    const { error: failure } = await createGroup(name.trim(), color)
    setBusy(false)
    if (failure) setError(friendlyError(failure))
    else onClose()
  }

  return (
    <Sheet
      title="New group"
      onClose={onClose}
      onSubmit={submit}
      footer={
        <>
          <Button tone="quiet" onClick={onClose}>
            Cancel
          </Button>
          <Button tone="primary" onClick={submit} disabled={!name.trim() || busy}>
            {busy ? 'Creating' : 'Create'}
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-3">
        {error ? <ErrorNote>{error}</ErrorNote> : null}
        <Field label="Name">
          <TextInput
            autoFocus
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Thursday study group"
          />
        </Field>
        <Field label="Colour" hint="Everyone starts on this colour and can change their own.">
          <ColorSwatchRow value={color} onChange={(hex) => setColor(hex ?? PALETTE[0])} />
        </Field>
      </div>
    </Sheet>
  )
}

function JoinGroupSheet({ onClose }: { onClose: () => void }) {
  const { joinGroup } = useStore()
  const [code, setCode] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function submit() {
    if (code.trim().length < 4 || busy) return
    setBusy(true)
    const { error: failure } = await joinGroup(code.trim())
    setBusy(false)
    if (failure) setError(friendlyError(failure))
    else onClose()
  }

  return (
    <Sheet
      title="Join a group"
      onClose={onClose}
      onSubmit={submit}
      footer={
        <>
          <Button tone="quiet" onClick={onClose}>
            Cancel
          </Button>
          <Button tone="primary" onClick={submit} disabled={code.trim().length < 4 || busy}>
            {busy ? 'Joining' : 'Join'}
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-3">
        {error ? <ErrorNote>{error}</ErrorNote> : null}
        <Field label="Join code" hint="Eight characters. Dashes and spaces do not matter.">
          <TextInput
            autoFocus
            value={code}
            onChange={(e) => setCode(e.target.value.toUpperCase())}
            placeholder="ABCD2345"
            className="num tracking-[0.18em]"
          />
        </Field>
      </div>
    </Sheet>
  )
}
