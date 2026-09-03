import Foundation
import Testing
@testable import TimeControlCore

@Suite struct WeekMathTests {
    let la = Calendar.app(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

    @Test func termStartingMidWeekNumbersFromItsMonday() {
        // Wed 2026-09-09 → Fri 2026-12-18
        let t = TermWeeks(termStart: DayKey(year: 2026, month: 9, day: 9), termEnd: DayKey(year: 2026, month: 12, day: 18))
        #expect(t.firstWeekStart == DayKey(year: 2026, month: 9, day: 7))
        #expect(t.weekCount == 15)
        #expect(t.weekNumber(of: DayKey(year: 2026, month: 9, day: 7)) == nil)   // before term start
        #expect(t.weekNumber(of: DayKey(year: 2026, month: 9, day: 9)) == 1)
        #expect(t.weekNumber(of: DayKey(year: 2026, month: 9, day: 13)) == 1)
        #expect(t.weekNumber(of: DayKey(year: 2026, month: 9, day: 14)) == 2)
        #expect(t.weekNumber(of: DayKey(year: 2026, month: 12, day: 18)) == 15)
        #expect(t.weekNumber(of: DayKey(year: 2026, month: 12, day: 19)) == nil)  // after term end
    }

    @Test func weekRangesClampToTerm() {
        let t = TermWeeks(termStart: DayKey(year: 2026, month: 9, day: 9), termEnd: DayKey(year: 2026, month: 12, day: 18))
        #expect(t.days(inWeek: 1) == DayKey(year: 2026, month: 9, day: 7)...DayKey(year: 2026, month: 9, day: 13))
        #expect(t.days(inWeeks: 1...1) == DayKey(year: 2026, month: 9, day: 9)...DayKey(year: 2026, month: 9, day: 13))
        #expect(t.days(inWeeks: 8...9) == DayKey(year: 2026, month: 10, day: 26)...DayKey(year: 2026, month: 11, day: 8))
        #expect(t.days(inWeeks: 15...15).upperBound == DayKey(year: 2026, month: 12, day: 18))
    }

    @Test func instantIsDSTSafe() {
        // 2026-03-08 is the spring-forward day in Los Angeles. `startOfDay + 600 min` would give 11:00.
        let spring = DayKey(year: 2026, month: 3, day: 8)
        let at10 = WeekMath.instant(day: spring, minute: 600, calendar: la)
        #expect(la.component(.hour, from: at10) == 10)
        #expect(la.component(.minute, from: at10) == 0)
        #expect(WeekMath.minuteOfDay(at10, calendar: la) == 600)
        #expect(at10.timeIntervalSince(spring.startDate(in: la)) == 9 * 3600)

        // 2026-11-01 is the fall-back day.
        let fall = DayKey(year: 2026, month: 11, day: 1)
        let at1030 = WeekMath.instant(day: fall, minute: 630, calendar: la)
        #expect(la.component(.hour, from: at1030) == 10)
        #expect(la.component(.minute, from: at1030) == 30)
        #expect(at1030.timeIntervalSince(fall.startDate(in: la)) == 11.5 * 3600)
    }
}
