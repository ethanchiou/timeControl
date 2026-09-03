import Foundation

/// A calendar day identified by an integer: days since 2000-01-01.
///
/// Day keys are what the app stores and queries on (SwiftData `#Predicate` cannot call `Calendar`).
/// They are independent of time zone: a key names a civil date, not an instant.
public struct DayKey: Hashable, Comparable, Codable, Sendable, Strideable, CustomStringConvertible {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// 2000-01-01, a Saturday.
    public static let epoch = DayKey(rawValue: 0)

    /// Days between 1970-01-01 and 2000-01-01.
    private static let unixEpochOffset = 10957

    // MARK: Civil date conversion (Howard Hinnant's algorithms; no Calendar needed)

    public init(year: Int, month: Int, day: Int) {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let daysSinceUnix = era * 146097 + doe - 719468
        self.rawValue = daysSinceUnix - DayKey.unixEpochOffset
    }

    public var civil: (year: Int, month: Int, day: Int) {
        let z = rawValue + DayKey.unixEpochOffset + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }

    public var year: Int { civil.year }
    public var month: Int { civil.month }
    public var day: Int { civil.day }

    // MARK: Date conversion

    /// The civil day that `date` falls on in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar = .app) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Start of this day in `calendar`'s time zone.
    public func startDate(in calendar: Calendar = .app) -> Date {
        let c = civil
        return calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day))!
    }

    public static func today(calendar: Calendar = .app, now: Date = Date()) -> DayKey {
        DayKey(now, calendar: calendar)
    }

    // MARK: Weeks

    /// Monday-first weekday of this day.
    public var weekday: Weekday {
        // 2000-01-01 (rawValue 0) was a Saturday, index 5.
        Weekday(rawValue: ((rawValue % 7) + 7 + 5) % 7)!
    }

    /// The Monday that starts this day's week.
    public var weekStart: DayKey {
        self - weekday.rawValue
    }

    /// Monday-first: the week starting on this day's Monday is `weekStart...weekStart+6`.
    public var week: ClosedRange<DayKey> {
        let start = weekStart
        return start...(start + 6)
    }

    // MARK: Strideable

    public func advanced(by n: Int) -> DayKey { DayKey(rawValue: rawValue + n) }
    public func distance(to other: DayKey) -> Int { other.rawValue - rawValue }

    public static func + (lhs: DayKey, rhs: Int) -> DayKey { lhs.advanced(by: rhs) }
    public static func - (lhs: DayKey, rhs: Int) -> DayKey { lhs.advanced(by: -rhs) }
    public static func - (lhs: DayKey, rhs: DayKey) -> Int { rhs.distance(to: lhs) }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String {
        let c = civil
        return String(format: "%04d-%02d-%02d", c.year, c.month, c.day)
    }
}

/// Monday-first weekday. Raw values are bit positions in a weekday mask.
public enum Weekday: Int, CaseIterable, Codable, Sendable, Comparable {
    case monday = 0, tuesday, wednesday, thursday, friday, saturday, sunday

    public var mask: Int { 1 << rawValue }

    public var shortName: String {
        switch self {
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        case .sunday: "Sun"
        }
    }

    public var name: String {
        switch self {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }

    /// Foundation's `Calendar.Component.weekday` value (Sunday = 1).
    public var foundationWeekday: Int { rawValue == 6 ? 1 : rawValue + 2 }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    public static func set(fromMask mask: Int) -> Set<Weekday> {
        Set(allCases.filter { mask & $0.mask != 0 })
    }

    public static func mask(of weekdays: some Sequence<Weekday>) -> Int {
        weekdays.reduce(0) { $0 | $1.mask }
    }
}

extension Calendar {
    /// Gregorian, Monday-first, current time zone. Used for every day-key/instant conversion in the app.
    public static var app: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.firstWeekday = 2
        return c
    }

    /// Same as `app` but pinned to a time zone; used by tests.
    public static func app(timeZone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.firstWeekday = 2
        return c
    }
}
