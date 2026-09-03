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

## Tests

```sh
(cd Packages/TimeControlCore && swift test)                                  # pure logic: engine, parser, rings, backup
xcodebuild -project TimeControl.xcodeproj -scheme TimeControl -destination 'platform=macOS' test   # app + services
```

## Debug launch flags (Debug builds only)

```
--sample-data        load a fixture term, courses, blackout, events, projects and todos (idempotent)
--section week       open on a section: today | week | todos | projects | terms | settings
--scale month        open the Week section at a scale: day | week | month
--palette            open the ⌘K quick-add palette
```

## Layout

```
Packages/TimeControlCore   pure Swift: DayKey, WeekMath, OccurrenceEngine, QuickAddParser, RingMath, Backup DTOs
TimeControl/App            app entry, AppState, RootView, menu commands
TimeControl/Models         SwiftData SchemaV1 models + spec mappers, ScheduleSnapshot
TimeControl/Features       Today, Week, Todos, Projects, Terms, Settings, CommandPalette, MenuBar, Shared
TimeControl/Services       Rollover, Notifications, CalendarMirror, Backup, SampleData
TimeControlTests           app-level tests (in-memory SwiftData)
```
