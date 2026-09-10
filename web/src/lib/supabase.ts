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
    flowType: 'pkce',
  },
})

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
