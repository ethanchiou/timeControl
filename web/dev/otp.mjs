#!/usr/bin/env node
/**
 * Print a six-digit sign-in code for a development account on the hosted project.
 *
 * The hosted project's default mailer only delivers to the project owner's address, so a throwaway
 * test account never receives its code by email. This asks the auth admin API for the same code the
 * email would have carried.
 *
 * Usage: node web/dev/otp.mjs tc-test-1@example.com
 *
 * The service role key is read from ~/.config/timecontrol/supabase.env at run time. It is never
 * written into the repo, never bundled into the app, and never printed.
 */

import { readFile } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join } from 'node:path'

const CONFIG = join(homedir(), '.config', 'timecontrol', 'supabase.env')

async function readConfig() {
  let text
  try {
    text = await readFile(CONFIG, 'utf8')
  } catch {
    throw new Error(`cannot read ${CONFIG}`)
  }
  const env = {}
  for (const line of text.split('\n')) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith('#')) continue
    const eq = trimmed.indexOf('=')
    if (eq < 0) continue
    env[trimmed.slice(0, eq).trim()] = trimmed
      .slice(eq + 1)
      .trim()
      .replace(/^["']|["']$/g, '')
  }
  return env
}

const email = process.argv[2]
if (!email || !email.includes('@')) {
  console.error('usage: node web/dev/otp.mjs <email>')
  process.exit(2)
}

const env = await readConfig()
const url = env.SUPABASE_URL
const key = env.SUPABASE_SERVICE_ROLE_KEY
if (!url || !key) {
  console.error(`SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must both be set in ${CONFIG}`)
  process.exit(1)
}

const response = await fetch(`${url}/auth/v1/admin/generate_link`, {
  method: 'POST',
  headers: {
    apikey: key,
    Authorization: `Bearer ${key}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({ type: 'magiclink', email }),
})

const body = await response.json().catch(() => null)
if (!response.ok) {
  // Report the status and the server's own message only. Nothing here echoes the key.
  console.error(`generate_link failed: ${response.status} ${body?.msg ?? body?.error ?? ''}`.trim())
  process.exit(1)
}

const code = body?.email_otp
if (!code) {
  console.error('no email_otp in the response')
  process.exit(1)
}

console.log(code)
