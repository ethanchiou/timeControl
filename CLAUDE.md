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
  `xcrun simctl launch <udid> com.ethanchiou.TimeControl --sample-data --section week`, `xcrun simctl io <udid> screenshot`.
  `screencapture` on the Mac needs Screen Recording permission and is not available to the agent.

## Conventions

- Days are `DayKey` (Int, days since 2000-01-01), never `Date`; weeks are the Monday's `DayKey`. Instants use
  `WeekMath.instant(day:minute:)`, never `startOfDay + minutes` (DST).
- Models map to Core spec structs (`series.spec`, `todo.spec`) before any logic runs; the engine never sees `@Model`.
- Every section view hosts its own `NavigationStack` (the iOS `TabView` provides none).
- Blackouts are non-destructive; deleting one restores occurrences. Exceptions are skip-only in v1.
- `Kind` is a code enum; per-kind user settings live in `UserDefaults` (see `NotificationSettings`, `CalendarMirrorSettings`).
- Shared files owned by the main agent when parallelising: `App/*`, `Models/*`, `project.yml`.

## SwiftData gotchas (both cost real time)

- Keep the `ModelContainer` alive. A `ModelContext` whose container was deallocated traps with a silent SIGTRAP on
  the next insert. Tests use a `Store { let container }` wrapper.
- `#Predicate` rejects force-unwraps at fetch time (`Unsupported Predicate … ForcedUnwrap`), silently under `try?`.
  Use `($0.dayKey ?? sentinel) < x` with the sentinel bound outside the macro, or filter in Swift.
- `List` nested in a `ScrollView` collapses to zero height; use a `VStack` of rows in compact layouts.
- `try #require(throwingCall())` does not compile when the call is a local throwing function; bind first.
