import Foundation
import SwiftUI
import TimeControlCore

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case today, upcoming, calendar, todos, projects, terms, settings

    /// The sidebar's `List(_:selection:)` tags each row with `Element.ID`, so this must be the
    /// section itself for the selection binding to ever match. A `String` id compiles and silently
    /// breaks every click.
    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .upcoming: "Upcoming"
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
        case .upcoming: "calendar.day.timeline.left"
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
    /// The rolling window the Upcoming section lists: the rest of today, seven days or thirty.
    var upcomingScale: CalendarScale = .week
    /// The eye filter, per scale: hide routine items (course occurrences and events marked routine)
    /// so only one-time items show. A month is mostly courses repeating, so it opens filtered; a day
    /// and a week have the room to show everything.
    var hidesRoutineByScale: [CalendarScale: Bool] = [.day: false, .week: false, .month: true]
    /// Upcoming is for what is coming that is not the timetable, so it opens on one-time items only;
    /// the eye reveals course occurrences and routine events.
    var hidesRoutineInUpcoming = true
    /// The eye's second flag, per scale: hide group items (events shared through a group). Off on a
    /// day and a week; a month opens with them hidden, like routine items, to keep the grid readable.
    var hidesGroupByScale: [CalendarScale: Bool] = [.day: false, .week: false, .month: true]
    /// Upcoming shows group events by default: they are exactly the one-time things it is for.
    var hidesGroupInUpcoming = false
    var isCommandPaletteShown = false
    /// Todos moved to today by the last rollover run; views show a subtle marker on them.
    var rolledOverTodoIDs: Set<UUID> = []

    /// The eye for what is on screen: the calendar's own scale, a day everywhere else (Today shows one).
    private var filteredScale: CalendarScale { section == .calendar ? calendarScale : .day }

    /// The eye filter for the view on screen. Reading and writing it leaves the other scales alone.
    var hidesRoutine: Bool {
        get { section == .upcoming ? hidesRoutineInUpcoming : (hidesRoutineByScale[filteredScale] ?? false) }
        set {
            if section == .upcoming {
                hidesRoutineInUpcoming = newValue
            } else {
                hidesRoutineByScale[filteredScale] = newValue
            }
        }
    }

    /// The eye's group flag for the view on screen, with the same per-scale memory as `hidesRoutine`.
    var hidesGroup: Bool {
        get { section == .upcoming ? hidesGroupInUpcoming : (hidesGroupByScale[filteredScale] ?? false) }
        set {
            if section == .upcoming {
                hidesGroupInUpcoming = newValue
            } else {
                hidesGroupByScale[filteredScale] = newValue
            }
        }
    }

    /// Both eye flags for the view on screen, as the snapshot takes them.
    var hiddenFilter: OccurrenceFilter {
        var filter: OccurrenceFilter = []
        if hidesRoutine { filter.insert(.routine) }
        if hidesGroup { filter.insert(.group) }
        return filter
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
