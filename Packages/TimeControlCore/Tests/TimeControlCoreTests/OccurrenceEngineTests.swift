import Foundation
import Testing
@testable import TimeControlCore

@Suite struct OccurrenceEngineTests {
    let la = Calendar.app(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

    // Fall 2026: Mon Sep 7 → Fri Dec 18, 15 weeks.
    let term = TermSpec(name: "Fall 2026", start: DayKey(year: 2026, month: 9, day: 7), end: DayKey(year: 2026, month: 12, day: 18))

    func d(_ m: Int, _ day: Int) -> DayKey { DayKey(year: 2026, month: m, day: day) }

    func course(_ title: String = "CS201", weekdays: Set<Weekday> = [.monday, .wednesday], interval: Int = 1, startWeek: Int = 1, endWeek: Int? = 14, kind: Kind = .course) -> SeriesSpec {
        SeriesSpec(title: title, kind: kind, term: term, weekdays: weekdays, startMinute: 600, endMinute: 690, intervalWeeks: interval, startWeek: startWeek, endWeek: endWeek)
    }

    func days(_ occ: [Occurrence]) -> [DayKey] { occ.map(\.day) }

    @Test func weeklyCourseHitsItsWeekdaysInsideItsWeekRange() {
        let occ = OccurrenceEngine.occurrences(in: d(9, 7)...d(9, 20), series: [course()], calendar: la)
        #expect(days(occ) == [d(9, 7), d(9, 9), d(9, 14), d(9, 16)])
        #expect(la.component(.hour, from: occ[0].start) == 10)
        #expect(la.component(.minute, from: occ[0].end) == 30)
        #expect(occ[0].id == "occ-\(occ[0].seriesID!.uuidString)-\(d(9, 7).rawValue)")
        // Week 15 (Dec 14–18) is past endWeek 14.
        let tail = OccurrenceEngine.occurrences(in: d(12, 7)...d(12, 18), series: [course()], calendar: la)
        #expect(days(tail) == [d(12, 7), d(12, 9)])
    }

    @Test func biweeklyParityComesFromStartWeek() {
        let s = course(weekdays: [.tuesday], interval: 2, startWeek: 2)
        let occ = OccurrenceEngine.occurrences(in: d(9, 7)...d(10, 11), series: [s], calendar: la)
        // Weeks 2, 4 → Sep 15, Sep 29. Weeks 1, 3, 5 skipped.
        #expect(days(occ) == [d(9, 15), d(9, 29)])
        #expect(s.occurs(inWeek: 1) == false)
        #expect(s.occurs(inWeek: 2))
        #expect(s.occurs(inWeek: 3) == false)
        #expect(s.occurs(inWeek: 4))
    }

    @Test func termStartingMidWeekDropsDaysBeforeIt() {
        let midWeek = TermSpec(name: "T", start: d(9, 9), end: d(12, 18))
        let s = SeriesSpec(title: "X", term: midWeek, weekdays: [.monday, .wednesday], startMinute: 540, endMinute: 600)
        let occ = OccurrenceEngine.occurrences(in: d(9, 7)...d(9, 16), series: [s], calendar: la)
        #expect(days(occ) == [d(9, 9), d(9, 14), d(9, 16)])
    }

    @Test func blackoutSuppressesOnlyMatchingKindsAndDays() {
        let cs = course()
        let exam = course("Midterm review", weekdays: [.monday], kind: .exam)
        // "Clear courses for weeks 8–9": Oct 26 – Nov 8.
        let b = BlackoutSpec(start: term.weeks.days(inWeeks: 8...9).lowerBound, end: term.weeks.days(inWeeks: 8...9).upperBound, kinds: [.course], reason: "Exams")
        let occ = OccurrenceEngine.occurrences(in: d(10, 19)...d(11, 11), series: [cs, exam], blackouts: [b], calendar: la)

        let suppressed = occ.filter(\.isSuppressed)
        let visible = occ.filter { !$0.isSuppressed }
        #expect(suppressed.allSatisfy { $0.kind == .course && $0.suppressedBy == b.id })
        #expect(days(suppressed) == [d(10, 26), d(10, 28), d(11, 2), d(11, 4)])
        // Exam-kind series inside the blackout stays visible; courses outside it stay visible.
        #expect(visible.contains { $0.kind == .exam && $0.day == d(10, 26) })
        #expect(visible.contains { $0.kind == .course && $0.day == d(10, 21) })
        #expect(visible.contains { $0.kind == .course && $0.day == d(11, 9) })

        // Empty kinds = everything recurring.
        let all = BlackoutSpec(start: d(10, 26), end: d(10, 26))
        let occAll = OccurrenceEngine.occurrences(on: d(10, 26), series: [cs, exam], blackouts: [all], calendar: la)
        #expect(occAll.count == 2 && occAll.allSatisfy(\.isSuppressed))
    }

    @Test func skippedExceptionRemovesExactlyOneOccurrence() {
        let cs = course()
        let skip = ExceptionSpec(seriesID: cs.id, day: d(9, 9))
        let occ = OccurrenceEngine.occurrences(in: d(9, 7)...d(9, 16), series: [cs], exceptions: [skip], calendar: la)
        #expect(days(occ) == [d(9, 7), d(9, 14), d(9, 16)])
        // An exception for another series does nothing.
        let other = ExceptionSpec(seriesID: UUID(), day: d(9, 7))
        #expect(OccurrenceEngine.occurrences(in: d(9, 7)...d(9, 16), series: [cs], exceptions: [other], calendar: la).count == 4)
    }

    @Test func eventsMergeInStartOrderAndAreNeverBlackedOut() {
        let cs = course()
        let interview = EventSpec(title: "Interview", kind: .interview, start: WeekMath.instant(day: d(9, 7), minute: 15 * 60, calendar: la), end: WeekMath.instant(day: d(9, 7), minute: 16 * 60, calendar: la))
        let early = EventSpec(title: "Dentist", kind: .appointment, start: WeekMath.instant(day: d(9, 7), minute: 8 * 60, calendar: la), end: WeekMath.instant(day: d(9, 7), minute: 9 * 60, calendar: la))
        let allDay = EventSpec(title: "Add/drop deadline", kind: .other, start: d(9, 7).startDate(in: la), end: d(9, 7).startDate(in: la), isAllDay: true)
        let outside = EventSpec(title: "Later", kind: .other, start: WeekMath.instant(day: d(9, 30), minute: 600, calendar: la), end: WeekMath.instant(day: d(9, 30), minute: 660, calendar: la))
        let b = BlackoutSpec(start: d(9, 7), end: d(9, 7))

        let occ = OccurrenceEngine.occurrences(on: d(9, 7), series: [cs], events: [interview, early, allDay, outside], blackouts: [b], calendar: la)
        #expect(occ.map(\.title) == ["Add/drop deadline", "Dentist", "CS201", "Interview"])
        #expect(occ.filter { $0.eventID != nil }.allSatisfy { !$0.isSuppressed })
        #expect(occ.first { $0.title == "CS201" }?.isSuppressed == true)
        #expect(occ[3].id == "evt-\(interview.id.uuidString)")
    }

    @Test func nextSkipsSuppressedAndPastOccurrences() {
        let cs = course()
        let b = BlackoutSpec(start: d(9, 7), end: d(9, 7), kinds: [.course])
        let now = WeekMath.instant(day: d(9, 7), minute: 9 * 60, calendar: la)
        let next = OccurrenceEngine.next(after: now, series: [cs], blackouts: [b], calendar: la)
        #expect(next?.day == d(9, 9))
        // Still in progress counts as next.
        let during = WeekMath.instant(day: d(9, 9), minute: 620, calendar: la)
        #expect(OccurrenceEngine.next(after: during, series: [cs], calendar: la)?.day == d(9, 9))
        let after = WeekMath.instant(day: d(9, 9), minute: 700, calendar: la)
        #expect(OccurrenceEngine.next(after: after, series: [cs], calendar: la)?.day == d(9, 14))
    }
}

@Suite struct RoutineFlagTests {
    let la = Calendar.app(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
    let term = TermSpec(name: "Fall 2026", start: DayKey(year: 2026, month: 9, day: 7), end: DayKey(year: 2026, month: 12, day: 18))

    @Test func seriesOccurrencesAreRoutineAndEventsOnlyWhenMarked() {
        let day = DayKey(year: 2026, month: 9, day: 7)
        let cs = SeriesSpec(title: "CS201", term: term, weekdays: [.monday], startMinute: 600, endMinute: 660)
        let gym = EventSpec(title: "Gym", kind: .personal, start: WeekMath.instant(day: day, minute: 420, calendar: la), end: WeekMath.instant(day: day, minute: 480, calendar: la), isRoutine: true)
        let interview = EventSpec(title: "Interview", kind: .interview, start: WeekMath.instant(day: day, minute: 900, calendar: la), end: WeekMath.instant(day: day, minute: 960, calendar: la))
        let occ = OccurrenceEngine.occurrences(on: day, series: [cs], events: [gym, interview], calendar: la)
        #expect(occ.map { ($0.title, $0.isRoutine) } .map { "\($0.0):\($0.1)" } == ["Gym:true", "CS201:true", "Interview:false"])
        #expect(occ.filter { !$0.isRoutine }.map(\.title) == ["Interview"])
    }
}
