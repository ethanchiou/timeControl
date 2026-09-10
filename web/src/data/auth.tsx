import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase'

interface AuthValue {
  session: Session | null
  userId: string | null
  email: string | null
  displayName: string
  /** False only while the very first session lookup is in flight. */
  ready: boolean
  requestCode: (email: string) => Promise<{ error: string | null }>
  verifyCode: (email: string, token: string) => Promise<{ error: string | null }>
  signOut: () => Promise<void>
  setDisplayName: (name: string) => Promise<{ error: string | null }>
}

const AuthContext = createContext<AuthValue | null>(null)

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [ready, setReady] = useState(false)
  const [displayName, setName] = useState('')

  useEffect(() => {
    let cancelled = false
    supabase.auth.getSession().then(({ data }) => {
      if (cancelled) return
      setSession(data.session)
      setReady(true)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((_event, next) => {
      setSession(next)
      setReady(true)
    })
    return () => {
      cancelled = true
      sub.subscription.unsubscribe()
    }
  }, [])

  const userId = session?.user.id ?? null

  useEffect(() => {
    if (!userId) {
      setName('')
      return
    }
    let cancelled = false
    void supabase
      .from('profiles')
      .select('display_name')
      .eq('id', userId)
      .maybeSingle()
      .then(({ data }) => {
        if (!cancelled) setName(data?.display_name ?? '')
      })
    return () => {
      cancelled = true
    }
  }, [userId])

  const requestCode = useCallback(async (email: string) => {
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { shouldCreateUser: true },
    })
    return { error: error?.message ?? null }
  }, [])

  const verifyCode = useCallback(async (email: string, token: string) => {
    const { error } = await supabase.auth.verifyOtp({ email, token, type: 'email' })
    return { error: error?.message ?? null }
  }, [])

  const signOut = useCallback(async () => {
    await supabase.auth.signOut()
  }, [])

  const setDisplayName = useCallback(
    async (name: string) => {
      if (!userId) return { error: 'Not signed in.' }
      const trimmed = name.trim()
      const { error } = await supabase
        .from('profiles')
        .update({ display_name: trimmed })
        .eq('id', userId)
      if (!error) setName(trimmed)
      return { error: error?.message ?? null }
    },
    [userId],
  )

  const value = useMemo<AuthValue>(
    () => ({
      session,
      userId,
      email: session?.user.email ?? null,
      displayName,
      ready,
      requestCode,
      verifyCode,
      signOut,
      setDisplayName,
    }),
    [session, userId, displayName, ready, requestCode, verifyCode, signOut, setDisplayName],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth(): AuthValue {
  const value = useContext(AuthContext)
  if (!value) throw new Error('useAuth must be used inside AuthProvider')
  return value
}
