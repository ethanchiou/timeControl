import Foundation
import SwiftUI
import TimeControlCore

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case today, calendar, todos, projects, terms, settings

    /// The sidebar's `List(_:selection:)` tags each row with `Element.ID`, so this must be the
    /// section itself for the selection binding to ever match. A `String` id compiles and silently
    /// breaks every click.
    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .calendar: "Calendar"
        case .todos: "Todos"
        case .projects: "Projects"
        case .terms: "Terms"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .today: "sun.max"
        case .calendar: "calendar"
        case .todos: "checklist"
        case .projects: "square.grid.2x2"
        case .terms: "graduationcap"
        case .settings: "gearshape"
        }
    }

    /// Accepts the section's raw name and the pre-rename alias "week" (debug flag, ⌘K "go week").
    static func named(_ raw: String) -> AppSection? {
        raw == "week" ? .calendar : AppSection(rawValue: raw)
    }
}

/// How much of the calendar the Week section shows at once.
enum CalendarScale: String, CaseIterable, Identifiable, Hashable {
    case day, week, month

    var id: Self { self }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }
}

/// Navigation and transient UI state shared across the window, the menu bar extra and the command palette.
@Observable
final class AppState {
    var section: AppSection = .today
    /// Day shown by Today/Todos.
    var selectedDay: DayKey = .today()
    /// Monday of the week shown by Week.
    var weekStart: DayKey = DayKey.today().weekStart
    /// Day, week or month in the Week section.
    var calendarScale: CalendarScale = .week
    /// The eye filter, per scale: hide routine items (course occurrences and events marked routine)
    /// so only one-time items show. A month is mostly courses repeating, so it opens filtered; a day
    /// and a week have the room to show everything.
    var hidesRoutineByScale: [CalendarScale: Bool] = [.day: false, .week: false, .month: true]
    var isCommandPaletteShown = false
    /// Todos moved to today by the last rollover run; views show a subtle marker on them.
    var rolledOverTodoIDs: Set<UUID> = []

    /// The eye for what is on screen: the calendar's own scale, a day everywhere else (Today shows one).
    private var filteredScale: CalendarScale { section == .calendar ? calendarScale : .day }

    /// The eye filter for the view on screen. Reading and writing it leaves the other scales alone.
    var hidesRoutine: Bool {
        get { hidesRoutineByScale[filteredScale] ?? false }
        set { hidesRoutineByScale[filteredScale] = newValue }
    }

    func goToToday() {
        let today = DayKey.today()
        selectedDay = today
        weekStart = today.weekStart
    }

    func show(day: DayKey) {
        selectedDay = day
        weekStart = day.weekStart
    }

    func shiftWeek(by weeks: Int) {
        weekStart = weekStart + 7 * weeks
        selectedDay = weekStart
    }

    func shiftDay(by days: Int) {
        show(day: selectedDay + days)
    }

    func shiftMonth(by months: Int) {
        show(day: selectedDay.addingMonths(months))
    }

    /// One page of whatever the calendar is currently showing.
    func shiftCalendar(by pages: Int) {
        switch calendarScale {
        case .day: shiftDay(by: pages)
        case .week: shiftWeek(by: pages)
        case .month: shiftMonth(by: pages)
        }
    }

    /// Pick a scale from the picker or a menu command. The calendar opens on the current day, week
    /// or month rather than wherever it was last left.
    func selectScale(_ scale: CalendarScale) {
        calendarScale = scale
        goToToday()
    }

    /// Open the calendar at a scale, from a menu command or the palette.
    func showCalendar(_ scale: CalendarScale) {
        selectScale(scale)
        section = .calendar
    }
}
