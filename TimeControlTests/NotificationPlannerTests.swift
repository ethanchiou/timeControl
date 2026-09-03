import Foundation
import Testing
import TimeControlCore
@testable import TimeControl

@MainActor
@Suite struct NotificationPlannerTests {
    let calendar = Calendar.app(timeZone: TimeZone(identifier: "UTC")!)
    let day = DayKey(year: 2026, month: 9, day: 9)

    var now: Date { WeekMath.instant(day: day, minute: 8 * 60, calendar: calendar) }

    func seriesOcc(
        kind: Kind = .course,
        startMinute: Int = 9 * 60,
        endMinute: Int = 10 * 60 + 20,
        isAllDay: Bool = false,
        location: String = "Science 110",
        suppressedBy: UUID? = nil,
        seriesID: UUID = UUID()
    ) -> Occurrence {
        Occurrence(
            source: .series(id: seriesID, day: day),
            title: "MATH240 Linear Algebra",
            kind: kind,
            day: day,
            start: WeekMath.instant(day: day, minute: startMinute, calendar: calendar),
            end: WeekMath.instant(day: day, minute: endMinute, calendar: calendar),
            isAllDay: isAllDay,
            location: location,
            suppressedBy: suppressedBy
        )
    }

    func eventOcc(
        id: UUID,
        kind: Kind = .exam,
        startMinute: Int = 9 * 60,
        endMinute: Int = 11 * 60,
        isAllDay: Bool = false,
        location: String = ""
    ) -> Occurrence {
        Occurrence(
            source: .event(id: id),
            title: "MATH240 Midterm",
            kind: kind,
            day: day,
            start: WeekMath.instant(day: day, minute: startMinute, calendar: calendar),
            end: WeekMath.instant(day: day, minute: endMinute, calendar: calendar),
            isAllDay: isAllDay,
            location: location
        )
    }

    @Test func seriesOccurrenceWithKindReminderProducesOneNotificationAtOffset() {
        let occ = seriesOcc()
        let planned = NotificationPlanner.plan(
            occurrences: [occ], eventOffsets: [:], seriesReminder: { _ in 10 },
            todos: [], todoDueHour: 9, now: now, calendar: calendar
        )
        #expect(planned.count == 1)
        #expect(planned[0].id == "tc-occ-\(occ.id)-10")
        #expect(planned[0].fireDate == occ.start.addingTimeInterval(-10 * 60))
        #expect(planned[0].kind == .course)
    }

    @Test func seriesOccurrenceWithNilKindReminderProducesNone() {
        let occ = seriesOcc(kind: .personal)
        let planned = NotificationPlanner.plan(
            occurrences: [occ], eventOffsets: [:], seriesReminder: { _ in nil },
            todos: [], todoDueHour: 9, now: now, calendar: calendar
        )
        #expect(planned.isEmpty)
    }

    @Test func suppressedOccurrenceProducesNone() {
        let occ = seriesOcc(suppressedBy: UUID())
        let planned = NotificationPlanner.plan(
            occurrences: [occ], eventOffsets: [:], seriesReminder: { _ in 10 },
            todos: [], todoDueHour: 9, now: now, calendar: calendar
        )
        #expect(planned.isEmpty)
    }

    @Test func allDayOccurrenceProducesNone() {
        let occ = seriesOcc(isAllDay: true)
        let planned = NotificationPlanner.plan(
            occurrences: [occ], eventOffsets: [:], seriesReminder: { _ in 10 },
            todos: [], todoDueHour: 9, now: now, calendar: calendar
        )
        #expect(planned.isEmpty)
    }

    @Test func eventWithMultipleOffsetsProducesDistinctNotifications() {
        let eventID = UUID()
        // Starts at 10:00 so both the at-time and 60-minute-before reminders (10:00, 9:00) are after `now` (08:00).
        let occ = eventOcc(id: eventID, startMinute: 10 * 60, endMinute: 12 * 60)
        let planned = NotificationPlanner.plan(
            occurrences: [occ], eventOffsets: [eventID: [0, 60]], seriesReminder: { _ in nil },
            todos: [], todoDueHour: 9, now: now, calendar: calendar
        )
        #expect(planned.count == 2)
        let ids = Set(planned.map(\.id))
        #expect(ids == ["tc-occ-\(occ.id)-0", "tc-occ-\(occ.id)-60"])
        // The 60-minute-before reminder fires earlier than the at-time one.
        #expect(planned.map(\.id) == ["tc-occ-\(occ.id)-60", "tc-occ-\(occ.id)-0"])
    }

    @Test func pastFireDatesAreDropped() {
        // now == 08:00; a reminder 30 min before a 08:10 start would fire at 07:40, already past.
        let occ = seriesOcc(startMinute: 8 * 60 + 10)
        let planned = NotificationPlanner.plan(
            occurrences: [occ], eventOffsets: [:], seriesReminder: { _ in 30 },
            todos: [], todoDueHour: 9, now: now, calendar: calendar
        )
        #expect(planned.isEmpty)
    }

    @Test func todosFireAtDueHourWithDueTodayBody() {
        let todoID = UUID()
        let todo = TodoReminderInput(id: todoID, title: "Finish outline", dueDay: day)
        let planned = NotificationPlanner.plan(
            occurrences: [], eventOffsets: [:], seriesReminder: { _ in nil },
            todos: [todo], todoDueHour: 9, now: now, calendar: calendar
        )
        #expect(planned.count == 1)
        #expect(planned[0].id == "tc-todo-\(todoID.uuidString)")
        #expect(planned[0].title == "Finish outline")
        #expect(planned[0].body == "Due today")
        #expect(planned[0].fireDate == WeekMath.instant(day: day, minute: 9 * 60, calendar: calendar))
        #expect(planned[0].kind == nil)
    }

    @Test func resultsAreOrderedByFireDate() {
        let earlyOcc = seriesOcc(startMinute: 9 * 60, seriesID: UUID())
        let lateTodo = TodoReminderInput(id: UUID(), title: "Later", dueDay: day)
        let planned = NotificationPlanner.plan(
            occurrences: [earlyOcc], eventOffsets: [:], seriesReminder: { _ in 5 },
            todos: [lateTodo], todoDueHour: 20, now: now, calendar: calendar
        )
        #expect(planned.count == 2)
        #expect(planned == planned.sorted { $0.fireDate < $1.fireDate })
        #expect(planned[0].fireDate < planned[1].fireDate)
    }

    @Test func truncatesToLimitWith60Inputs() {
        let todos = (0..<60).map { offset in
            TodoReminderInput(id: UUID(), title: "Todo \(offset)", dueDay: day + offset)
        }
        let planned = NotificationPlanner.plan(
            occurrences: [], eventOffsets: [:], seriesReminder: { _ in nil },
            todos: todos, todoDueHour: 9, now: now, calendar: calendar
        )
        #expect(planned.count == NotificationPlanner.limit)
        #expect(planned == planned.sorted { $0.fireDate < $1.fireDate })
        // The earliest 50 due days are kept; the last 10 are dropped.
        #expect(planned.last?.fireDate == WeekMath.instant(day: day + 49, minute: 9 * 60, calendar: calendar))
    }

    @Test func idsAreStableAcrossTwoCalls() {
        let occ = seriesOcc()
        let todo = TodoReminderInput(id: UUID(), title: "Stable", dueDay: day)
        func run() -> [String] {
            NotificationPlanner.plan(
                occurrences: [occ], eventOffsets: [:], seriesReminder: { _ in 10 },
                todos: [todo], todoDueHour: 9, now: now, calendar: calendar
            ).map(\.id)
        }
        #expect(run() == run())
    }
}
