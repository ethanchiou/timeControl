import Foundation
import SwiftUI
import TimeControlCore

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case today, week, todos, projects, terms, settings

    var id: String { rawValue }

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

/// Navigation and transient UI state shared across the window, the menu bar extra and the command palette.
@Observable
final class AppState {
    var section: AppSection = .today
    /// Day shown by Today/Todos.
    var selectedDay: DayKey = .today()
    /// Monday of the week shown by Week.
    var weekStart: DayKey = DayKey.today().weekStart
    /// Show occurrences hidden by a blackout, greyed out.
    var showsHiddenOccurrences = false
    var isCommandPaletteShown = false

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
}
