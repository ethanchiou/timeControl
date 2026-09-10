# TimeControl: next steps

State on 2026-09-10, branch `feature/supabase-groups`. What works, what to do to run it elsewhere,
what stands between the web client and a public Vercel deployment, and what comes after.

## 1. Running from another machine

Everything the app needs is in the repo except two secrets files. On a fresh clone:

1. **Native app.** Install Xcode 26 and XcodeGen (`brew install xcodegen`). Copy
   `Config/Supabase.example.xcconfig` to `Config/Supabase.xcconfig` and fill in the project URL and
   publishable key (from `~/.config/timecontrol/supabase.env` on the original Mac, or the Supabase
   dashboard → Project Settings → API). Then `xcodegen generate` and build as in the README. Without
   the file the app still builds and runs local-only.
2. **Web client.** `cd web && npm install`, copy `.env.example` to `.env.local` with the same two
   values, `npm run dev`.
3. **Supabase CLI** (only to change the backend). `brew install supabase/tap/supabase`,
   `supabase login`, `supabase link --project-ref vdbsfdaclvnixmhicchv` (asks for the database
   password, also in `~/.config/timecontrol/`). Migrations: `supabase db push`. Auth settings:
   `supabase config push`.
4. **Local data does not travel** with the clone: the store lives in the app container. Sign in on
   the new machine and the account's data pulls down; or export a JSON backup and import it.

The hosted integration test needs the service-role key in the environment; see `CLAUDE.md`.

## 2. Web client on Vercel

### Ready now

- Static Vite build (`npm run build` → `web/dist`), no server, 143 kB gzipped.
- `web/vercel.json` rewrites every non-asset path to `index.html` for browser routing.
- Sign-in magic links return to whatever origin served the page (`emailRedirectTo`).
- Configuration is two build-time env vars: `VITE_SUPABASE_URL`, `VITE_SUPABASE_KEY`.

### To deploy (about ten minutes)

1. In Vercel, import `ethanchiou/timeControl`, set **Root Directory** to `web`, framework Vite,
   build `npm run build`, output `dist` (the defaults once the root is set).
2. Add the two env vars for Production and Preview with the hosted project's URL and publishable key.
3. Deploy. Note the production URL (and any custom domain).
4. In `supabase/config.toml`, set `[auth] site_url` to the production URL and add it (plus preview
   URLs if wanted) to `additional_redirect_urls`, keeping `http://localhost:5173` and
   `timecontrol://auth-callback`. Run `supabase config push`.
5. Optional: a custom domain in Vercel, then repeat step 4 for it.

### Before real users can sign in

- **Custom SMTP on the Supabase project.** The free tier's default mailer delivers only to the
  project owner's address and refuses custom templates. Dashboard → Authentication → Emails → SMTP
  (Resend or Brevo free tiers are enough), then uncomment `[auth.email.template.magic_link]` in
  `supabase/config.toml` and `supabase config push` so emails carry the six-digit code. Until then
  only the owner receives sign-in mail, and everyone else would need a code from
  `node web/dev/otp.mjs <email>` (service-role key, never for end users).
- **Rate limits.** Default email rate limit is a few per hour; raise `auth.rate_limit.email_sent`
  in the dashboard once SMTP is set.
- **Remove the throwaway users** `tc-test-1@example.com` and `tc-test-2@example.com`
  (Authentication → Users). The integration test deletes its own.

### Worth doing soon after

- Vercel Analytics or a simple error reporter; today errors only reach the console.
- A `robots.txt` and an app icon/favicon for the web build (the native icon exists in the asset
  catalog).
- Terms and courses editing on the web (v1 shows them read-only).

## 3. Native app

- **Sign-in on the hosted project** works through the magic link (opens the app via
  `timecontrol://auth-callback`, allow-listed) or a code from `web/dev/otp.mjs`; codes by email
  need the SMTP step above.
- **Distribution.** The Mac build is ad-hoc signed and runs locally; installing on an iPhone needs
  an Apple ID in Xcode. TestFlight, Sign in with Apple, iCloud and push notifications all need a
  paid developer account.
- **OAuth later.** Google works on both clients without a paid account: enable the provider in
  `config.toml`, add the callback URL in Google Cloud, and call `signInWithOAuth`; the native app
  already handles the URL-scheme callback.
- **Realtime while backgrounded** is not a thing without push; the app pulls on launch, foreground,
  save and while open. That is by design for v1.
- **Known UI nit (pre-existing).** On the iPhone the week bar's Today button and eye sit behind the
  overflow menu; a layout pass could move them into the header row.

## 4. Backend hygiene

- Migrations are append-only under `supabase/migrations`; the contract is `supabase/SCHEMA.md`.
- The free tier has no point-in-time recovery; the native app writes daily JSON backups and can
  export one manually. Consider a scheduled `pg_dump` (Supabase CLI: `supabase db dump`) if the data
  matters.
- Never commit `Config/Supabase.xcconfig`, `web/.env.local`, or anything with the service-role key.
- The local Docker stack is configured on ports 563xx to coexist with other projects' stacks, but
  needs free disk to start; the hosted project is the working backend and the integration test
  targets it.
