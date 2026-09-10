import Foundation
import Testing
import TimeControlCore
@testable import TimeControl

@Suite struct UpcomingAgendaTests {
    let today = DayKey(year: 2026, month: 9, day: 9)
    let la = Calendar.app(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

    func occurrence(_ title: String, day: DayKey, start: Int, end: Int, allDay: Bool = false, suppressed: Bool = false) -> Occurrence {
        Occurrence(
            source: .event(id: UUID()), title: title, kind: .other, day: day,
            start: WeekMath.instant(day: day, minute: start, calendar: la),
            end: WeekMath.instant(day: day, minute: end, calendar: la),
            isAllDay: allDay, suppressedBy: suppressed ? UUID() : nil
        )
    }

    @Test func windowsRollForwardFromToday() {
        #expect(UpcomingAgenda.days(for: .day, from: today) == today...today)
        #expect(UpcomingAgenda.days(for: .week, from: today).count == 7)
        #expect(UpcomingAgenda.days(for: .month, from: today).count == 30)
        #expect(UpcomingAgenda.days(for: .month, from: today).lowerBound == today)
    }

    /// Noon: breakfast is over, the lecture is running, the rest is still to come. Yesterday and a
    /// blacked-out occurrence never show.
    @Test func pendingKeepsWhatHasNotEndedYet() {
        let now = WeekMath.instant(day: today, minute: 12 * 60, calendar: la)
        let over = occurrence("Breakfast", day: today, start: 8 * 60, end: 9 * 60)
        let running = occurrence("Lecture", day: today, start: 11 * 60, end: 13 * 60)
        let later = occurrence("Dentist", day: today, start: 15 * 60, end: 16 * 60)
        let allDay = occurrence("Deadline", day: today, start: 0, end: 0, allDay: true)
        let tomorrow = occurrence("Gym", day: today + 1, start: 7 * 60, end: 8 * 60)
        let yesterday = occurrence("Old", day: today - 1, start: 20 * 60, end: 21 * 60)
        let hidden = occurrence("Blacked out", day: today + 2, start: 9 * 60, end: 10 * 60, suppressed: true)
        let kept = UpcomingAgenda.pending([over, running, later, allDay, tomorrow, yesterday, hidden], now: now, today: today)
        #expect(kept.map(\.title) == ["Lecture", "Dentist", "Deadline", "Gym"])
    }

    @Test func groupsSortDaysAndKeepDisplayOrderWithinADay() {
        let late = occurrence("Late", day: today + 1, start: 18 * 60, end: 19 * 60)
        let early = occurrence("Early", day: today + 1, start: 9 * 60, end: 10 * 60)
        let allDay = occurrence("All day", day: today + 1, start: 0, end: 0, allDay: true)
        let soon = occurrence("Soon", day: today, start: 14 * 60, end: 15 * 60)
        let groups = UpcomingAgenda.groups([late, early, allDay, soon])
        #expect(groups.map(\.day) == [today, today + 1])
        #expect(groups[0].occurrences.map(\.title) == ["Soon"])
        #expect(groups[1].occurrences.map(\.title) == ["All day", "Early", "Late"])
    }

    @Test func onlyTodayAndTomorrowGetNames() {
        #expect(UpcomingAgenda.relativeName(today, today: today) == "Today")
        #expect(UpcomingAgenda.relativeName(today + 1, today: today) == "Tomorrow")
        #expect(UpcomingAgenda.relativeName(today + 2, today: today) == nil)
        #expect(UpcomingAgenda.relativeName(today - 1, today: today) == nil)
    }
}
