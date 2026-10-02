import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_KEY

if (!url || !key) {
  throw new Error(
    'Missing VITE_SUPABASE_URL or VITE_SUPABASE_KEY. Copy web/.env.example to web/.env.local and fill it in.',
  )
}

export const supabase = createClient(url, key, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    // A magic link drops the session in the URL fragment, so let the client pick it up.
    detectSessionInUrl: true,
    // Implicit, not PKCE: a mail app opens the link in whatever browser it likes, usually not the
    // one that asked for it. PKCE leaves its code verifier in the requesting browser's storage, so
    // anywhere else the `?code=` callback finds no verifier and is silently treated as an ordinary
    // page load (the first-link-never-works bug). The implicit flow carries the session itself in
    // the fragment, so any browser can finish the sign-in, and the client clears the fragment.
    flowType: 'implicit',
  },
})

/**
 * Why the last sign-in link failed, read once at load and wiped from the address bar.
 *
 * A link that is expired, already used, or aimed at an origin the project does not allow comes back
 * as `#error=...&error_code=...` carrying no session. The client reports that only through the
 * promise returned by its own initialisation, which `getSession()` discards, so without this the
 * page simply shows the sign-in form again and says nothing about why.
 */
export const signInLinkError: string | null = takeSignInLinkError()

function takeSignInLinkError(): string | null {
  if (typeof window === 'undefined') return null
  const hash = new URLSearchParams(window.location.hash.replace(/^#/, ''))
  const query = new URLSearchParams(window.location.search)
  const code = hash.get('error_code') ?? query.get('error_code')
  const description = hash.get('error_description') ?? query.get('error_description')
  if (!code && !description) return null

  // An error callback carries no tokens, so nothing here is still wanted by the auth client.
  // Clearing it stops a reload from reporting a link the person has already given up on.
  for (const name of ['error', 'error_code', 'error_description']) query.delete(name)
  const search = query.toString()
  window.history.replaceState(
    window.history.state,
    '',
    window.location.pathname + (search ? `?${search}` : ''),
  )

  if (code === 'otp_expired') {
    return 'That sign-in link has expired or was already used. Send yourself a new one.'
  }
  return description?.replace(/\+/g, ' ') ?? 'That sign-in link did not work. Send yourself a new one.'
}

/** A new client-generated id. Rows are upserted by id, so the same UUID is the same record. */
export function newId(): string {
  return crypto.randomUUID()
}

/**
 * The messages the schema raises, in words a person can act on.
 * Anything unrecognised falls back to the server's own text.
 */
const KNOWN_ERRORS: Record<string, string> = {
  group_limit_reached: 'You can be in five groups at a time. Leave one first.',
  invalid_join_code: 'No group has that code. Check it and try again.',
  only_owner_can_delete_group: 'Only the person who made the group can delete it.',
  group_name_required: 'Give the group a name.',
  not_authenticated: 'Your session expired. Sign in again.',
}

export function friendlyError(error: unknown): string {
  if (!error) return ''
  const message =
    typeof error === 'string'
      ? error
      : ((error as { message?: string }).message ?? String(error))
  for (const [code, text] of Object.entries(KNOWN_ERRORS)) {
    if (message.includes(code)) return text
  }
  return message
}
