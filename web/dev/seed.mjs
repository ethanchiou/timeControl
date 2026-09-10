#!/usr/bin/env node
/**
 * Development fixtures for the hosted project.
 *
 * The local Docker stack is not available on this machine, so there is no local Postgres to load a
 * .sql file into. This does the same job through the REST API as a real signed-in user, which also
 * means every row it writes has to satisfy row-level security, exactly as the app does.
 *
 * Everything is keyed to fixed UUIDs, so running it twice is the same as running it once.
 *
 *   node web/dev/seed.mjs                                  fill tc-test-1 with a term and todos
 *   node web/dev/seed.mjs --email tc-test-2@example.com     the same, for a second account
 *   node web/dev/seed.mjs --email tc-test-2@example.com --join ABCD2345 --group-event
 *                                                          join a group and put an event in it
 *
 * The service role key is read from ~/.config/timecontrol/supabase.env at run time, only to mint a
 * sign-in code the way an inbox would. It is never written into the repo and never printed.
 */

import { readFile } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join } from 'node:path'

const CONFIG = join(homedir(), '.config', 'timecontrol', 'supabase.env')

async function readEnvFile(path) {
  const text = await readFile(path, 'utf8')
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

function arg(name, fallback = null) {
  const i = process.argv.indexOf(`--${name}`)
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback
}

const email = arg('email', 'tc-test-1@example.com')
const joinCode = arg('join')
const wantsGroupEvent = process.argv.includes('--group-event')

const config = await readEnvFile(CONFIG)
const url = config.SUPABASE_URL
const serviceKey = config.SUPABASE_SERVICE_ROLE_KEY
const anonKey =
  config.SUPABASE_PUBLISHABLE_KEY ??
  (await readEnvFile(new URL('../.env.local', import.meta.url).pathname)).VITE_SUPABASE_KEY

if (!url || !serviceKey || !anonKey) {
  console.error(`SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY and a publishable key must be set`)
  process.exit(1)
}

/** Days since 2000-01-01 for a civil date, the same algorithm the app uses. */
function dayKey(year, month, day) {
  const idiv = (a, b) => Math.trunc(a / b)
  const y = month <= 2 ? year - 1 : year
  const era = idiv(y >= 0 ? y : y - 399, 400)
  const yoe = y - era * 400
  const mp = (month + 9) % 12
  const doy = idiv(153 * mp + 2, 5) + day - 1
  const doe = yoe * 365 + idiv(yoe, 4) - idiv(yoe, 100) + doy
  return era * 146097 + doe - 719468 - 10957
}

async function signIn() {
  const link = await fetch(`${url}/auth/v1/admin/generate_link`, {
    method: 'POST',
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ type: 'magiclink', email }),
  })
  const linkBody = await link.json()
  if (!link.ok) throw new Error(`generate_link: ${link.status} ${linkBody?.msg ?? ''}`)

  const verify = await fetch(`${url}/auth/v1/verify`, {
    method: 'POST',
    headers: { apikey: anonKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'email', email, token: linkBody.email_otp }),
  })
  const session = await verify.json()
  if (!verify.ok) throw new Error(`verify: ${verify.status} ${session?.msg ?? ''}`)
  return { token: session.access_token, userId: session.user.id }
}

const { token, userId } = await signIn()
const auth = {
  apikey: anonKey,
  Authorization: `Bearer ${token}`,
  'Content-Type': 'application/json',
}

async function upsert(table, rows) {
  const response = await fetch(`${url}/rest/v1/${table}?on_conflict=id`, {
    method: 'POST',
    headers: { ...auth, Prefer: 'resolution=merge-duplicates,return=minimal' },
    body: JSON.stringify(rows),
  })
  if (!response.ok) throw new Error(`${table}: ${response.status} ${await response.text()}`)
  console.log(`${table}: ${rows.length}`)
}

async function rpc(name, args) {
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: auth,
    body: JSON.stringify(args),
  })
  const body = await response.json().catch(() => null)
  if (!response.ok) throw new Error(`${name}: ${response.status} ${body?.message ?? ''}`)
  return body
}

/** Fixed ids, namespaced per account so two test users never collide. */
const suffix = email.includes('tc-test-2') ? '2' : '1'
const id = (n) => `0000000${suffix}-0000-4000-8000-${String(n).padStart(12, '0')}`

// A term around today so the seeded courses land on the calendar you are looking at.
const now = new Date()
const termStart = dayKey(now.getFullYear(), now.getMonth() + 1, 1)
const termEnd = termStart + 15 * 7

await upsert('terms', [
  {
    id: id(1),
    user_id: userId,
    name: 'Autumn 2026',
    start_day_key: termStart,
    end_day_key: termEnd,
    is_archived: false,
  },
])

await upsert('series', [
  {
    id: id(10),
    user_id: userId,
    term_id: id(1),
    title: 'Thermodynamics',
    kind: 'course',
    weekdays_mask: 0b0000101, // Monday and Wednesday
    start_minute: 9 * 60,
    end_minute: 10 * 60 + 30,
    interval_weeks: 1,
    start_week: 1,
    end_week: 15,
    location: 'Hewlett 200',
    notes: '',
    color_hex: null,
  },
  {
    id: id(11),
    user_id: userId,
    term_id: id(1),
    title: 'Thermo section',
    kind: 'tutorial',
    weekdays_mask: 0b0001000, // Thursday
    start_minute: 13 * 60,
    end_minute: 14 * 60,
    interval_weeks: 1,
    start_week: 1,
    end_week: 15,
    location: 'Gates B03',
    notes: '',
    color_hex: null,
  },
  {
    id: id(12),
    user_id: userId,
    term_id: id(1),
    title: 'Fluids lab',
    kind: 'course',
    weekdays_mask: 0b0000010, // Tuesday
    start_minute: 14 * 60,
    end_minute: 17 * 60,
    interval_weeks: 2, // fortnightly, from week 2
    start_week: 2,
    end_week: 14,
    location: 'Building 530',
    notes: '',
    color_hex: '#06B6D4',
  },
])

await upsert('blackouts', [
  {
    id: id(20),
    user_id: userId,
    term_id: id(1),
    start_day_key: termStart + 7 * 7,
    end_day_key: termStart + 9 * 7 - 1,
    kinds: ['course'],
    reason: 'Midterm week',
  },
])

await upsert('projects', [
  {
    id: id(30),
    user_id: userId,
    title: 'Senior thesis',
    summary: '',
    notes: '',
    status: 'active',
    priority: 2,
    color_hex: '#A855F7',
    sort_order: 0,
  },
])

const today = dayKey(now.getFullYear(), now.getMonth() + 1, now.getDate())
const monday = today - (((today % 7) + 7 + 5) % 7)

await upsert('todos', [
  {
    id: id(40),
    user_id: userId,
    project_id: null,
    title: 'Read chapter 7 before section',
    notes: '',
    priority: 2,
    is_done: false,
    day_key: today,
    week_key: null,
    due_day_key: today,
    sort_order: 0,
  },
  {
    id: id(41),
    user_id: userId,
    project_id: id(30),
    title: 'Email Professor Nakashima about the lab slot',
    notes: '',
    priority: 1,
    is_done: false,
    day_key: today,
    week_key: null,
    due_day_key: today + 2,
    sort_order: 1,
  },
  {
    id: id(42),
    user_id: userId,
    project_id: id(30),
    title: 'Draft the methods section',
    notes: '',
    priority: 3,
    is_done: false,
    day_key: null,
    week_key: monday,
    due_day_key: monday + 4,
    sort_order: 2,
  },
  {
    id: id(43),
    user_id: userId,
    project_id: null,
    title: 'Renew the library loan',
    notes: '',
    priority: 4,
    is_done: true,
    day_key: today,
    week_key: null,
    due_day_key: null,
    sort_order: 3,
  },
  {
    id: id(44),
    user_id: userId,
    project_id: null,
    title: 'Find a summer housing sublet',
    notes: '',
    priority: 3,
    is_done: false,
    day_key: null,
    week_key: null,
    due_day_key: null,
    sort_order: 4,
  },
])

if (joinCode) {
  const group = await rpc('join_group', { p_code: joinCode })
  const joined = Array.isArray(group) ? group[0] : group
  console.log(`joined group: ${joined.name}`)

  if (wantsGroupEvent) {
    const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 16, 0, 0)
    const end = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 17, 30, 0)
    await upsert('events', [
      {
        id: id(50),
        user_id: userId,
        group_id: joined.id,
        title: 'Whiteboard the entropy problems',
        kind: 'course',
        start_at: start.toISOString(),
        end_at: end.toISOString(),
        is_all_day: false,
        location: 'Green Library basement',
        notes: '',
        reminder_offsets_minutes: [30],
        is_routine: false,
        color_hex: null,
      },
    ])
  }
}

console.log(`done for ${email}`)
