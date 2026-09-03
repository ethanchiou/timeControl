import Foundation
import SwiftUI
import TimeControlCore

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case today, week, todos, projects, terms, settings

    /// The sidebar's `List(_:selection:)` tags each row with `Element.ID`, so this must be the
    /// section itself for the selection binding to ever match. A `String` id compiles and silently
    /// breaks every click.
    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "Week"
        case .todos: "Todos"
        case .projects: "Projects"
        case .terms: "Terms"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .today: "sun.max"
        case .week: "calendar"
        case .todos: "checklist"
        case .projects: "square.grid.2x2"
        case .terms: "graduationcap"
        case .settings: "gearshape"
        }
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
    /// Show occurrences hidden by a blackout, greyed out.
    var showsHiddenOccurrences = false
    var isCommandPaletteShown = false
    /// Todos moved to today by the last rollover run; views show a subtle marker on them.
    var rolledOverTodoIDs: Set<UUID> = []

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

    /// Open the calendar at a scale, from a menu command or the palette.
    func showCalendar(_ scale: CalendarScale) {
        calendarScale = scale
        section = .week
    }
}
