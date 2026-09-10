# CLAUDE.md — TimeControl

Native SwiftUI + SwiftData scheduler, one multiplatform target (macOS 15+ / iOS 18+), Swift 6 strict
concurrency, app target defaults to MainActor isolation. Pure logic lives in `Packages/TimeControlCore`.

## Commands

- Regenerate the project after adding/removing files (the pbxproj lists files explicitly):
  `xcodegen generate -q`
- Build: `xcodebuild -project TimeControl.xcodeproj -scheme TimeControl -destination 'platform=macOS' -quiet build`
  and `-destination 'generic/platform=iOS Simulator'`. Both must stay green.
- Core tests: `cd Packages/TimeControlCore && swift test`. App tests: `xcodebuild … -destination 'platform=macOS' test`.
- Concurrent builds: give each parallel worker its own `-derivedDataPath` to avoid build-database locks.
- Simulator smoke test: build with `-destination 'platform=iOS Simulator,id=<udid>'`, `xcrun simctl install`,
  `xcrun simctl launch <udid> com.ethanchiou.TimeControl --sample-data --section calendar`, `xcrun simctl io <udid> screenshot`.
  `screencapture` on the Mac needs Screen Recording permission and is not available to the agent.
- `-quiet` builds print nothing on success; check the exit code or the app product, not the output.
- Backend: `supabase/migrations` + `supabase/config.toml`, pushed with `supabase db push -p <db password>` and
  `supabase config push` (needs `supabase login`). Contract in `supabase/SCHEMA.md`. Client keys in
  `Config/Supabase.xcconfig` (gitignored; copy `Supabase.example.xcconfig`). Secrets for this machine live in
  `~/.config/timecontrol/` and are never committed.
- Hosted integration test (creates and deletes throwaway users):
  `TEST_RUNNER_SUPABASE_SERVICE_ROLE_KEY=… xcodebuild … test -only-testing:TimeControlTests/SyncIntegrationTests`.
  `xcodebuild` forwards only `TEST_RUNNER_`-prefixed variables to the test host.

## Conventions

- Days are `DayKey` (Int, days since 2000-01-01), never `Date`; weeks are the Monday's `DayKey`. Instants use
  `WeekMath.instant(day:minute:)`, never `startOfDay + minutes` (DST).
- Models map to Core spec structs (`series.spec`, `todo.spec`) before any logic runs; the engine never sees `@Model`.
- Every section view hosts its own `NavigationStack` (the iOS `TabView` provides none).
- Blackouts are non-destructive; deleting one restores occurrences. Exceptions are skip-only in v1.
- `Kind` is a code enum; per-kind user settings live in `UserDefaults` (see `NotificationSettings`, `CalendarMirrorSettings`).
- Shared files owned by the main agent when parallelising: `App/*`, `Models/*`, `Services/Sync/*`,
  `Services/Supabase/*`, `project.yml`, `supabase/*`.
- The group model is `SharedGroup`; never name a type `Group`, it shadows SwiftUI's and breaks every view.
- Schema: `SchemaV2` is the live versioned schema; migration is SwiftData's automatic lightweight inference, with
  no staged plan on purpose (a staged plan refuses stores written by any model it does not know exactly, and
  stores in the wild were written by several intermediate models). Add only optional/defaulted attributes and new
  entities, bump `versionIdentifier`, and keep `LegacyStoreTests` green against `TimeControlTests/Fixtures`.
- Sync: clients never hard-delete on the server; `SyncTracker` records every main-context save into the outbox and
  `SyncService` pushes upserts/tombstones parents-first, then pulls by per-table cursor. Writes that mirror the
  server go through `tracker.applyingRemote(in:)` so they stay out of the outbox. `syncedAt` on a model is the
  server's `updated_at` last applied; nil means never synced.
- Wire structs (`SyncRows.swift`) and other value types used from `@Sendable` closures are declared `nonisolated`;
  the app target defaults to MainActor isolation, which would otherwise make their `Codable` conformances isolated.

## SwiftData gotchas (both cost real time)

- Keep the `ModelContainer` alive. A `ModelContext` whose container was deallocated traps with a silent SIGTRAP on
  the next insert. Tests use a `Store { let container }` wrapper.
- `#Predicate` rejects force-unwraps at fetch time (`Unsupported Predicate … ForcedUnwrap`), silently under `try?`.
  Use `($0.dayKey ?? sentinel) < x` with the sentinel bound outside the macro, or filter in Swift.
- `List` nested in a `ScrollView` collapses to zero height; use a `VStack` of rows in compact layouts.
- `try #require(throwingCall())` does not compile when the call is a local throwing function; bind first.
- A `ModelContext` cannot be carried into `MainActor.assumeIsolated` from a notification closure (strict
  concurrency rejects it however it is wrapped); pass only `ObjectIdentifier(context)` and compare against a
  context stored on the observer.
