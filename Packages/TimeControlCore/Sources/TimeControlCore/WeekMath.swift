import Foundation

/// Week numbering for a term. Week 1 starts on the Monday of the week containing `termStart`.
public struct TermWeeks: Hashable, Sendable {
    public let termStart: DayKey
    public let termEnd: DayKey

    public init(termStart: DayKey, termEnd: DayKey) {
        self.termStart = termStart
        self.termEnd = max(termEnd, termStart)
    }

    /// Monday of week 1.
    public var firstWeekStart: DayKey { termStart.weekStart }

    /// Number of (possibly partial) weeks the term spans.
    public var weekCount: Int { (termEnd - firstWeekStart) / 7 + 1 }

    /// 1-based week number of `day`, or nil when `day` is outside `termStart...termEnd`.
    public func weekNumber(of day: DayKey) -> Int? {
        guard day >= termStart, day <= termEnd else { return nil }
        return (day - firstWeekStart) / 7 + 1
    }

    /// Monday of week `n` (1-based). Not clamped to the term.
    public func weekStart(ofWeek n: Int) -> DayKey {
        firstWeekStart + 7 * (n - 1)
    }

    /// The seven days of week `n`, not clamped to the term.
    public func days(inWeek n: Int) -> ClosedRange<DayKey> {
        let start = weekStart(ofWeek: n)
        return start...(start + 6)
    }

    /// The days of weeks `first...last`, clamped to the term. Used for "clear weeks 8–9".
    public func days(inWeeks range: ClosedRange<Int>) -> ClosedRange<DayKey> {
        let lo = max(weekStart(ofWeek: range.lowerBound), termStart)
        let hi = min(weekStart(ofWeek: range.upperBound) + 6, termEnd)
        return lo...max(lo, hi)
    }
}

public enum WeekMath {
    /// The instant at `minute` minutes past local midnight on `day`. DST-safe (never `startOfDay + minutes`).
    public static func instant(day: DayKey, minute: Int, calendar: Calendar = .app) -> Date {
        let c = day.civil
        let comps = DateComponents(year: c.year, month: c.month, day: c.day, hour: minute / 60, minute: minute % 60)
        return calendar.date(from: comps)!
    }

    /// Minutes since local midnight of `date`'s day.
    public static func minuteOfDay(_ date: Date, calendar: Calendar = .app) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return c.hour! * 60 + c.minute!
    }

    /// "10:30" style label for a minute-of-day, using the calendar's locale conventions.
    public static func timeLabel(minute: Int, calendar: Calendar = .app) -> String {
        let date = instant(day: .epoch, minute: minute, calendar: calendar)
        return date.formatted(.dateTime.hour().minute())
    }
}
