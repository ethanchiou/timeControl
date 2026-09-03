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

    @Test func monthStartLengthAndDays() {
        let mid = DayKey(year: 2026, month: 9, day: 17)
        #expect(mid.monthStart == DayKey(year: 2026, month: 9, day: 1))
        #expect(mid.monthLength == 30)
        #expect(mid.monthDays == DayKey(year: 2026, month: 9, day: 1)...DayKey(year: 2026, month: 9, day: 30))

        #expect(DayKey(year: 2024, month: 2, day: 10).monthLength == 29)
        #expect(DayKey(year: 2026, month: 2, day: 10).monthLength == 28)
        #expect(DayKey(year: 2100, month: 2, day: 10).monthLength == 28)
        #expect(DayKey(year: 2026, month: 12, day: 25).monthLength == 31)
        #expect(DayKey(year: 2026, month: 12, day: 25).monthDays.upperBound == DayKey(year: 2026, month: 12, day: 31))
    }

    @Test func monthGridCoversTheMonthInWholeWeeks() {
        // September 2026 starts on a Tuesday and ends on a Wednesday.
        let grid = DayKey(year: 2026, month: 9, day: 17).monthGrid
        #expect(grid.lowerBound == DayKey(year: 2026, month: 8, day: 31))
        #expect(grid.upperBound == DayKey(year: 2026, month: 10, day: 4))
        #expect(grid.lowerBound.weekday == .monday)
        #expect(grid.upperBound.weekday == .sunday)
        #expect((grid.upperBound - grid.lowerBound + 1) % 7 == 0)
    }

    @Test func monthGridIsAlwaysWholeWeeksAroundTheWholeMonth() {
        var day = DayKey(year: 2023, month: 1, day: 1)
        while day < DayKey(year: 2029, month: 1, day: 1) {
            let grid = day.monthGrid
            let days = day.monthDays
            #expect(grid.lowerBound.weekday == .monday, "\(day)")
            #expect(grid.upperBound.weekday == .sunday, "\(day)")
            #expect((grid.upperBound - grid.lowerBound + 1) % 7 == 0, "\(day)")
            #expect(grid.contains(days.lowerBound) && grid.contains(days.upperBound), "\(day)")
            // Never a whole blank week of padding at either end.
            #expect(days.lowerBound - grid.lowerBound < 7, "\(day)")
            #expect(grid.upperBound - days.upperBound < 7, "\(day)")
            day = day.addingMonths(1)
        }
    }

    @Test func addingMonthsClampsToTheShorterMonth() {
        let jan31 = DayKey(year: 2026, month: 1, day: 31)
        #expect(jan31.addingMonths(1) == DayKey(year: 2026, month: 2, day: 28))
        #expect(DayKey(year: 2024, month: 1, day: 31).addingMonths(1) == DayKey(year: 2024, month: 2, day: 29))
        #expect(DayKey(year: 2026, month: 3, day: 31).addingMonths(-1) == DayKey(year: 2026, month: 2, day: 28))
    }

    @Test func addingMonthsCrossesYearsInBothDirections() {
        let dec = DayKey(year: 2026, month: 12, day: 15)
        #expect(dec.addingMonths(1) == DayKey(year: 2027, month: 1, day: 15))
        #expect(dec.addingMonths(13) == DayKey(year: 2028, month: 1, day: 15))
        let jan = DayKey(year: 2026, month: 1, day: 15)
        #expect(jan.addingMonths(-1) == DayKey(year: 2025, month: 12, day: 15))
        #expect(jan.addingMonths(-13) == DayKey(year: 2024, month: 12, day: 15))
        #expect(jan.addingMonths(0) == jan)
        // Round trip over a long run of months.
        for n in -40...40 {
            #expect(jan.addingMonths(n).addingMonths(-n) == jan, "\(n)")
        }
    }
}
