# TimeControl

A native SwiftUI scheduler for students: recurring courses inside a term, one-action reversible
"clear courses for weeks 8–9" blackouts, one-off events (interviews, exams, appointments), daily and
weekly todo lists with progress rings, and a projects board for larger goals. macOS first, iOS from the
same target.

## Build

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
The `.xcodeproj` is generated from `project.yml` and is not checked in.

```sh
xcodegen generate
xcodebuild -project TimeControl.xcodeproj -scheme TimeControl -destination 'platform=macOS' build
xcodebuild -project TimeControl.xcodeproj -scheme TimeControl -destination 'generic/platform=iOS Simulator' build
```

Or open `TimeControl.xcodeproj` in Xcode after generating it. The Mac app is signed to run locally
(ad-hoc); installing on an iPhone needs an Apple ID added in Xcode.

### Account, sync and groups (optional)

The app runs local-only until you sign in. Signing in (email plus a six-digit code) syncs every
term, course, event, project and todo to a Supabase project and unlocks groups: shared events that
appear on every member's calendar in the group's colour, joined by an eight-character code.

Copy `Config/Supabase.example.xcconfig` to `Config/Supabase.xcconfig` and fill in the project URL
and publishable key, then regenerate. Without that file the build still works and the Account
section says so. The backend schema, access rules and conventions are in `supabase/SCHEMA.md`; the
web client that shares the same backend lives in `web/`.

## Tests

```sh
(cd Packages/TimeControlCore && swift test)                                  # pure logic: engine, parser, rings, backup
xcodebuild -project TimeControl.xcodeproj -scheme TimeControl -destination 'platform=macOS' test   # app + services
```

## Debug launch flags (Debug builds only)

```
--sample-data        load a fixture term, courses, blackout, events, projects and todos (idempotent)
--section calendar   open on a section: today | upcoming | calendar | todos | projects | terms | settings ("week" still works)
--hide-routine       start with the eye filter on (routine items hidden)
--scale month        open the Week section at a scale: day | week | month
--palette            open the ⌘K quick-add palette
```

## Layout

```
Packages/TimeControlCore   pure Swift: DayKey, WeekMath, OccurrenceEngine, QuickAddParser, RingMath, Backup DTOs
TimeControl/App            app entry, AppState, RootView, menu commands
TimeControl/Models         SwiftData models (SchemaV2 live, SchemaV1 frozen) + spec mappers, ScheduleSnapshot
TimeControl/Features       Today, Upcoming, Week, Month, Todos, Projects, Terms, Settings, CommandPalette, MenuBar, Shared
TimeControl/Services       Rollover, Notifications, CalendarMirror, Backup, SampleData, Supabase (auth, groups), Sync
TimeControlTests           app-level tests (in-memory SwiftData); SyncIntegrationTests runs against the hosted project
supabase/                  migrations, auth config, SCHEMA.md contract
web/                       the web client (Vite + React), same backend
```
