import Foundation
import Testing
@testable import TimeControlCore

@Suite struct DayKeyTests {
    @Test func epochIsSaturdayJan1st2000() {
        let k = DayKey.epoch
        #expect(k.civil == (2000, 1, 1))
        #expect(k.weekday == .saturday)
    }

    @Test func civilRoundTripAcrossEpoch() {
        for (y, m, d) in [(1999, 12, 31), (2000, 2, 29), (2024, 2, 29), (2026, 9, 7), (2100, 3, 1), (1970, 1, 1)] {
            let k = DayKey(year: y, month: m, day: d)
            #expect(k.civil == (y, m, d), "\(y)-\(m)-\(d)")
        }
        #expect(DayKey(year: 1999, month: 12, day: 31).rawValue == -1)
        #expect(DayKey(year: 1970, month: 1, day: 1).rawValue == -10957)
    }

    @Test func weekdaysAndWeekStart() {
        let mon = DayKey(year: 2026, month: 9, day: 7)
        #expect(mon.weekday == .monday)
        #expect(mon.weekStart == mon)
        let thu = DayKey(year: 2026, month: 9, day: 10)
        #expect(thu.weekday == .thursday)
        #expect(thu.weekStart == mon)
        let sun = DayKey(year: 2026, month: 9, day: 13)
        #expect(sun.weekday == .sunday)
        #expect(sun.weekStart == mon)
        #expect(sun.week == mon...sun)
        // Negative keys still land on the right weekday.
        #expect(DayKey(year: 1999, month: 12, day: 31).weekday == .friday)
    }

    @Test func dateConversionUsesCalendarTimeZone() throws {
        let la = Calendar.app(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        let tokyo = Calendar.app(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        // 2026-09-07 23:30 in LA is 2026-09-08 15:30 in Tokyo.
        let instant = try #require(la.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 23, minute: 30)))
        #expect(DayKey(instant, calendar: la) == DayKey(year: 2026, month: 9, day: 7))
        #expect(DayKey(instant, calendar: tokyo) == DayKey(year: 2026, month: 9, day: 8))
        #expect(DayKey(year: 2026, month: 9, day: 7).startDate(in: la) == la.startOfDay(for: instant))
    }

    @Test func strideAndArithmetic() {
        let a = DayKey(year: 2026, month: 9, day: 7)
        let b = a + 13
        #expect(b - a == 13)
        #expect(Array(a...(a + 2)).map(\.day) == [7, 8, 9])
        #expect((a...b).count == 14)
        #expect(a.description == "2026-09-07")
    }

    @Test func weekdayMasks() {
        let set: Set<Weekday> = [.monday, .wednesday, .friday]
        let mask = Weekday.mask(of: set)
        #expect(mask == 0b10101)
        #expect(Weekday.set(fromMask: mask) == set)
        #expect(Weekday.sunday.foundationWeekday == 1)
        #expect(Weekday.monday.foundationWeekday == 2)
    }
}
