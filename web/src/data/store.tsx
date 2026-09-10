import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react'
import type {
  BlackoutSpec,
  EventGroup,
  EventSpec,
  ExceptionSpec,
  SeriesSpec,
  TermSpec,
  TodoSpec,
} from '@/core'
import { newId, supabase } from '@/lib/supabase'
import {
  resolveGroup,
  toBlackoutSpec,
  toEventSpec,
  toExceptionSpec,
  toSeriesSpec,
  toTermSpec,
  toTodoSpec,
} from '@/lib/mappers'
import type {
  BlackoutRow,
  EventRow,
  ExceptionRow,
  GroupMemberRow,
  GroupRow,
  ProfileRow,
  ProjectRow,
  SeriesRow,
  TermRow,
  TodoRow,
} from '@/lib/rows'
import { useAuth } from './auth'

export interface GroupMember {
  userId: string
  displayName: string
  role: 'owner' | 'member'
  colorOverrideHex: string | null
}

export interface GroupSummary {
  id: string
  name: string
  /** The group's own colour, which everyone starts from. */
  colorHex: string
  /** What this viewer sees: their override if they set one, else the group colour. */
  resolvedColorHex: string
  myColorOverride: string | null
  joinCode: string
  createdBy: string
  myRole: 'owner' | 'member'
  members: GroupMember[]
}

export interface Project {
  id: string
  title: string
  colorHex: string
}

export interface Snapshot {
  terms: TermSpec[]
  series: SeriesSpec[]
  blackouts: BlackoutSpec[]
  exceptions: ExceptionSpec[]
  events: EventSpec[]
  todos: TodoSpec[]
  projects: Project[]
  groups: GroupSummary[]
}

const EMPTY: Snapshot = {
  terms: [],
  series: [],
  blackouts: [],
  exceptions: [],
  events: [],
  todos: [],
  projects: [],
  groups: [],
}

/** What a caller hands us to write an event. Ids are client-generated so a save is an upsert. */
export interface EventDraft {
  id: string
  title: string
  kind: string
  startAt: Date
  endAt: Date
  isAllDay: boolean
  location: string
  notes: string
  reminderOffsetsMinutes: number[]
  isRoutine: boolean
  colorHex: string | null
  groupId: string | null
}

export interface TodoDraft {
  id: string
  title: string
  notes: string
  priority: number
  isDone: boolean
  dayKey: number | null
  weekKey: number | null
  dueDayKey: number | null
  projectId: string | null
}

interface StoreValue {
  data: Snapshot
  loading: boolean
  error: string | null
  reload: () => Promise<void>
  saveEvent: (draft: EventDraft) => Promise<{ error: string | null }>
  deleteEvent: (id: string) => Promise<{ error: string | null }>
  saveTodo: (draft: TodoDraft) => Promise<{ error: string | null }>
  setTodoDone: (id: string, done: boolean) => Promise<{ error: string | null }>
  deleteTodo: (id: string) => Promise<{ error: string | null }>
  createGroup: (name: string, colorHex: string) => Promise<{ error: string | null }>
  joinGroup: (code: string) => Promise<{ error: string | null }>
  leaveGroup: (groupId: string) => Promise<{ error: string | null }>
  setGroupColorOverride: (
    groupId: string,
    colorHex: string | null,
  ) => Promise<{ error: string | null }>
}

const StoreContext = createContext<StoreValue | null>(null)

const alive = <T extends { deleted_at: string | null }>(rows: T[] | null): T[] =>
  (rows ?? []).filter((r) => r.deleted_at === null)

/** Every table the app reads. A change to any of them means the snapshot is stale. */
const SYNCED_TABLES = [
  'terms',
  'series',
  'blackouts',
  'occurrence_exceptions',
  'events',
  'projects',
  'todos',
  'groups',
  'group_members',
] as const

/** A membership row with the embedded profile the foreign key makes available. */
type MemberRowWithProfile = GroupMemberRow & { profiles?: { display_name: string } | null }

export function StoreProvider({ children }: { children: React.ReactNode }) {
  const { userId } = useAuth()
  const [data, setData] = useState<Snapshot>(EMPTY)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const reloadTimer = useRef<number | null>(null)

  const reload = useCallback(async (isRetry = false) => {
    if (!userId) {
      setData(EMPTY)
      setLoading(false)
      return
    }
    // Row-level security already scopes every one of these to what the viewer may see.
    const [terms, series, blackouts, exceptions, events, projects, todos, groups, members, profiles] =
      await Promise.all([
        supabase.from('terms').select('*').is('deleted_at', null),
        supabase.from('series').select('*').is('deleted_at', null),
        supabase.from('blackouts').select('*').is('deleted_at', null),
        supabase.from('occurrence_exceptions').select('*').is('deleted_at', null),
        supabase.from('events').select('*').is('deleted_at', null),
        supabase.from('projects').select('*').is('deleted_at', null),
        supabase.from('todos').select('*').is('deleted_at', null),
        supabase.from('groups').select('*').is('deleted_at', null),
        supabase.from('group_members').select('*, profiles(display_name)'),
        supabase.from('profiles').select('id, display_name'),
      ])

    const failure = [terms, series, blackouts, exceptions, events, projects, todos, groups, members, profiles]
      .map((r) => r.error)
      .find(Boolean)
    if (failure) {
      // A token minted a moment ago can read as future-dated to the API for a second or two. That
      // is not something to put in front of a person who has just signed in, so try again once.
      if (failure.message.includes('issued at future') && !isRetry) {
        window.setTimeout(() => void reloadRef.current?.(true), 1500)
        return
      }
      setError(failure.message)
      setLoading(false)
      return
    }
    setError(null)

    const memberRows = (members.data ?? []) as MemberRowWithProfile[]
    const groupRows = alive((groups.data ?? []) as GroupRow[])
    const names = new Map<string, string>()
    for (const p of (profiles.data ?? []) as ProfileRow[]) {
      names.set(p.id, p.display_name || 'Someone')
    }
    // group_members.user_id also points at profiles, so a roster arrives with its names attached.
    for (const m of memberRows) {
      const embedded = m.profiles?.display_name
      if (embedded) names.set(m.user_id, embedded)
    }

    const groupSummaries: GroupSummary[] = groupRows.map((g) => {
      const roster = memberRows.filter((m) => m.group_id === g.id)
      const mine = roster.find((m) => m.user_id === userId)
      return {
        id: g.id,
        name: g.name,
        colorHex: g.color_hex,
        resolvedColorHex: mine?.color_override_hex ?? g.color_hex,
        myColorOverride: mine?.color_override_hex ?? null,
        joinCode: g.join_code,
        createdBy: g.created_by,
        myRole: mine?.role ?? 'member',
        members: roster
          .map((m) => ({
            userId: m.user_id,
            displayName: names.get(m.user_id) ?? 'Someone',
            role: m.role,
            colorOverrideHex: m.color_override_hex,
          }))
          .sort((a, b) =>
            a.role === b.role ? a.displayName.localeCompare(b.displayName) : a.role === 'owner' ? -1 : 1,
          ),
      }
    })

    const groupsForEvents = new Map<string, EventGroup>(
      groupRows.map((g) => [
        g.id,
        resolveGroup(
          g,
          memberRows.find((m) => m.group_id === g.id && m.user_id === userId),
        ),
      ]),
    )

    const termSpecs = alive((terms.data ?? []) as TermRow[]).map(toTermSpec)
    const termsById = new Map(termSpecs.map((t) => [t.id, t]))

    const seriesSpecs: SeriesSpec[] = []
    for (const row of alive((series.data ?? []) as SeriesRow[])) {
      const term = row.term_id ? termsById.get(row.term_id) : undefined
      // A series without a live term has no week numbering, so it cannot be placed on a calendar.
      if (term) seriesSpecs.push(toSeriesSpec(row, term))
    }

    const exceptionSpecs: ExceptionSpec[] = []
    for (const row of alive((exceptions.data ?? []) as ExceptionRow[])) {
      const spec = toExceptionSpec(row)
      if (spec) exceptionSpecs.push(spec)
    }

    setData({
      terms: termSpecs.sort((a, b) => b.start - a.start),
      series: seriesSpecs,
      blackouts: alive((blackouts.data ?? []) as BlackoutRow[]).map(toBlackoutSpec),
      exceptions: exceptionSpecs,
      events: alive((events.data ?? []) as EventRow[]).map((row) =>
        toEventSpec(row, userId, groupsForEvents, names),
      ),
      todos: alive((todos.data ?? []) as TodoRow[]).map(toTodoSpec),
      projects: alive((projects.data ?? []) as ProjectRow[]).map((p) => ({
        id: p.id,
        title: p.title,
        colorHex: p.color_hex,
      })),
      groups: groupSummaries.sort((a, b) => a.name.localeCompare(b.name)),
    })
    setLoading(false)
  }, [userId])

  // The retry above needs to call the current reload without making reload depend on itself.
  const reloadRef = useRef<((isRetry?: boolean) => Promise<void>) | null>(null)
  reloadRef.current = reload

  useEffect(() => {
    setLoading(true)
    void reload()
  }, [reload])

  /** Several changes usually land together, so collapse them into one refetch. */
  const scheduleReload = useCallback(() => {
    if (reloadTimer.current !== null) window.clearTimeout(reloadTimer.current)
    reloadTimer.current = window.setTimeout(() => {
      reloadTimer.current = null
      void reload()
    }, 250)
  }, [reload])

  useEffect(() => {
    if (!userId) return
    // Postgres Changes honour RLS, so this only ever wakes us for rows we can already read.
    // Every synced table is listened to, so a term or a todo changed in the native app lands here
    // without a reload, the same way a friend's group event does.
    const channel = SYNCED_TABLES.reduce(
      (channel, table) =>
        channel.on('postgres_changes', { event: '*', schema: 'public', table }, scheduleReload),
      supabase.channel('timecontrol-changes'),
    ).subscribe()
    return () => {
      void supabase.removeChannel(channel)
    }
  }, [userId, scheduleReload])

  const saveEvent = useCallback(
    async (draft: EventDraft) => {
      if (!userId) return { error: 'Not signed in.' }
      const { error } = await supabase.from('events').upsert({
        id: draft.id,
        user_id: userId,
        group_id: draft.groupId,
        title: draft.title,
        kind: draft.kind,
        start_at: draft.startAt.toISOString(),
        end_at: draft.endAt.toISOString(),
        is_all_day: draft.isAllDay,
        location: draft.location,
        notes: draft.notes,
        reminder_offsets_minutes: draft.reminderOffsetsMinutes,
        is_routine: draft.isRoutine,
        color_hex: draft.colorHex,
      })
      if (!error) await reload()
      return { error: error?.message ?? null }
    },
    [userId, reload],
  )

  const softDelete = useCallback(
    async (table: 'events' | 'todos', id: string) => {
      const { error } = await supabase
        .from(table)
        .update({ deleted_at: new Date().toISOString() })
        .eq('id', id)
      if (!error) await reload()
      return { error: error?.message ?? null }
    },
    [reload],
  )

  const saveTodo = useCallback(
    async (draft: TodoDraft) => {
      if (!userId) return { error: 'Not signed in.' }
      const { error } = await supabase.from('todos').upsert({
        id: draft.id,
        user_id: userId,
        project_id: draft.projectId,
        title: draft.title,
        notes: draft.notes,
        priority: draft.priority,
        is_done: draft.isDone,
        completed_at: draft.isDone ? new Date().toISOString() : null,
        day_key: draft.dayKey,
        week_key: draft.weekKey,
        due_day_key: draft.dueDayKey,
      })
      if (!error) await reload()
      return { error: error?.message ?? null }
    },
    [userId, reload],
  )

  const setTodoDone = useCallback(
    async (id: string, done: boolean) => {
      // Ticking a box should feel instant, so paint it first and let the write catch up.
      setData((prev) => ({
        ...prev,
        todos: prev.todos.map((t) => (t.id === id ? { ...t, isDone: done } : t)),
      }))
      const { error } = await supabase
        .from('todos')
        .update({ is_done: done, completed_at: done ? new Date().toISOString() : null })
        .eq('id', id)
      await reload()
      return { error: error?.message ?? null }
    },
    [reload],
  )

  const createGroup = useCallback(
    async (name: string, colorHex: string) => {
      const { error } = await supabase.rpc('create_group', {
        p_name: name,
        p_color_hex: colorHex,
      })
      if (!error) await reload()
      return { error: error?.message ?? null }
    },
    [reload],
  )

  const joinGroup = useCallback(
    async (code: string) => {
      const { error } = await supabase.rpc('join_group', { p_code: code })
      if (!error) await reload()
      return { error: error?.message ?? null }
    },
    [reload],
  )

  const leaveGroup = useCallback(
    async (groupId: string) => {
      const { error } = await supabase.rpc('leave_group', { p_group_id: groupId })
      if (!error) await reload()
      return { error: error?.message ?? null }
    },
    [reload],
  )

  const setGroupColorOverride = useCallback(
    async (groupId: string, colorHex: string | null) => {
      if (!userId) return { error: 'Not signed in.' }
      const { error } = await supabase
        .from('group_members')
        .update({ color_override_hex: colorHex })
        .eq('group_id', groupId)
        .eq('user_id', userId)
      if (!error) await reload()
      return { error: error?.message ?? null }
    },
    [userId, reload],
  )

  const value = useMemo<StoreValue>(
    () => ({
      data,
      loading,
      error,
      reload,
      saveEvent,
      deleteEvent: (id) => softDelete('events', id),
      saveTodo,
      setTodoDone,
      deleteTodo: (id) => softDelete('todos', id),
      createGroup,
      joinGroup,
      leaveGroup,
      setGroupColorOverride,
    }),
    [
      data,
      loading,
      error,
      reload,
      saveEvent,
      softDelete,
      saveTodo,
      setTodoDone,
      createGroup,
      joinGroup,
      leaveGroup,
      setGroupColorOverride,
    ],
  )

  return <StoreContext.Provider value={value}>{children}</StoreContext.Provider>
}

export function useStore(): StoreValue {
  const value = useContext(StoreContext)
  if (!value) throw new Error('useStore must be used inside StoreProvider')
  return value
}

export { newId }
