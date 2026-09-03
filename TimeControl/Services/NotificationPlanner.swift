import Foundation
import TimeControlCore

/// A local notification ready to hand to `UNUserNotificationCenter`. Pure data: no `UserNotifications` import here.
struct PlannedNotification: Hashable, Sendable {
    var id: String
    var title: String
    var body: String
    var fireDate: Date
    var kind: Kind?
}

/// What the planner needs to know about a todo to schedule its due-day reminder.
struct TodoReminderInput: Hashable, Sendable {
    var id: UUID
    var title: String
    var dueDay: DayKey
}

/// Turns occurrences and todos into a flat, ready-to-schedule list of notifications.
///
/// Pure and side-effect free so it can be exhaustively unit tested: no `UserNotifications` import,
/// no dates read from `Date()` internally (`now` is a parameter).
enum NotificationPlanner {
    /// Hard cap on notifications scheduled at once (`UNUserNotificationCenter` limits pending requests).
    static let limit = 50

    /// - Parameters:
    ///   - occurrences: Series and event occurrences to consider. Suppressed and all-day occurrences
    ///     never produce reminders.
    ///   - eventOffsets: Reminder lead times (minutes) per event id, from `EventSpec.reminderOffsetsMinutes`.
    ///     An empty (or missing) array means no reminder; one notification is planned per offset.
    ///   - seriesReminder: Lead time (minutes) for a series occurrence's kind; `nil` means no reminder.
    ///   - todos: Open todos with a due day; each fires once, at `todoDueHour` on that day.
    static func plan(
        occurrences: [Occurrence],
        eventOffsets: [UUID: [Int]],
        seriesReminder: (Kind) -> Int?,
        todos: [TodoReminderInput],
        todoDueHour: Int,
        now: Date,
        calendar: Calendar = .app
    ) -> [PlannedNotification] {
        var result: [PlannedNotification] = []

        for occurrence in occurrences where !occurrence.isSuppressed && !occurrence.isAllDay {
            if occurrence.seriesID != nil {
                if let minutes = seriesReminder(occurrence.kind) {
                    result.append(makeOccurrenceNotification(occurrence, offsetMinutes: minutes))
                }
            } else if let eventID = occurrence.eventID {
                for offset in eventOffsets[eventID] ?? [] {
                    result.append(makeOccurrenceNotification(occurrence, offsetMinutes: offset))
                }
            }
        }

        for todo in todos {
            let fireDate = WeekMath.instant(day: todo.dueDay, minute: todoDueHour * 60, calendar: calendar)
            result.append(
                PlannedNotification(id: "tc-todo-\(todo.id.uuidString)", title: todo.title, body: "Due today", fireDate: fireDate, kind: nil)
            )
        }

        return result
            .filter { $0.fireDate > now }
            .sorted { $0.fireDate != $1.fireDate ? $0.fireDate < $1.fireDate : $0.id < $1.id }
            .prefix(limit)
            .map { $0 }
    }

    private static func makeOccurrenceNotification(_ occurrence: Occurrence, offsetMinutes: Int) -> PlannedNotification {
        let fireDate = occurrence.start.addingTimeInterval(-Double(offsetMinutes) * 60)
        return PlannedNotification(
            id: "tc-occ-\(occurrence.id)-\(offsetMinutes)",
            title: occurrence.title,
            body: body(for: occurrence, offsetMinutes: offsetMinutes),
            fireDate: fireDate,
            kind: occurrence.kind
        )
    }

    private static func body(for occurrence: Occurrence, offsetMinutes: Int) -> String {
        let lead: String
        if offsetMinutes == 0 {
            lead = "starting now"
        } else if offsetMinutes < 60 {
            lead = "in \(offsetMinutes) min"
        } else {
            lead = "in \(offsetMinutes / 60) h"
        }
        let start = occurrence.start.formatted(date: .omitted, time: .shortened)
        let end = occurrence.end.formatted(date: .omitted, time: .shortened)
        var text = "\(lead) · \(start)–\(end)"
        if !occurrence.location.isEmpty {
            text += " · \(occurrence.location)"
        }
        return text
    }
}
