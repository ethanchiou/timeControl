import Foundation

// Value-type mirrors of the app's SwiftData models. The engine, parser and ring math only see these,
// so they stay Sendable, testable with `swift test`, and free of persistence concerns.

public struct TermSpec: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var start: DayKey
    public var end: DayKey

    public init(id: UUID = UUID(), name: String, start: DayKey, end: DayKey) {
        self.id = id
        self.name = name
        self.start = start
        self.end = end
    }

    public var weeks: TermWeeks { TermWeeks(termStart: start, termEnd: end) }
    public var days: ClosedRange<DayKey> { start...max(start, end) }
}

/// A recurring course/meeting inside a term.
public struct SeriesSpec: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var kind: Kind
    public var term: TermSpec
    public var weekdays: Set<Weekday>
    /// Minutes since local midnight. `endMinute > startMinute`.
    public var startMinute: Int
    public var endMinute: Int
    /// 1 = weekly, 2 = biweekly.
    public var intervalWeeks: Int
    /// 1-based, term-relative, inclusive.
    public var startWeek: Int
    public var endWeek: Int
    public var location: String
    public var colorHex: String?

    public init(
        id: UUID = UUID(),
        title: String,
        kind: Kind = .course,
        term: TermSpec,
        weekdays: Set<Weekday>,
        startMinute: Int,
        endMinute: Int,
        intervalWeeks: Int = 1,
        startWeek: Int = 1,
        endWeek: Int? = nil,
        location: String = "",
        colorHex: String? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.term = term
        self.weekdays = weekdays
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.intervalWeeks = max(1, intervalWeeks)
        self.startWeek = max(1, startWeek)
        self.endWeek = endWeek ?? term.weeks.weekCount
        self.location = location
        self.colorHex = colorHex
    }

    /// Whether this series has an occurrence in term week `w` (ignores weekday).
    public func occurs(inWeek w: Int) -> Bool {
        w >= startWeek && w <= endWeek && (w - startWeek) % intervalWeeks == 0
    }

    /// Whether this series has an occurrence on `day`.
    public func occurs(on day: DayKey) -> Bool {
        guard weekdays.contains(day.weekday), let w = term.weeks.weekNumber(of: day) else { return false }
        return occurs(inWeek: w)
    }
}

/// A one-off event: interview, exam, appointment.
public struct EventSpec: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var kind: Kind
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String
    public var reminderOffsetsMinutes: [Int]

    public init(
        id: UUID = UUID(),
        title: String,
        kind: Kind,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        location: String = "",
        reminderOffsetsMinutes: [Int] = []
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.start = start
        self.end = max(end, start)
        self.isAllDay = isAllDay
        self.location = location
        self.reminderOffsetsMinutes = reminderOffsetsMinutes
    }
}

/// Suppresses recurring occurrences of the given kinds (empty = all kinds) over a day range.
/// Non-destructive: remove the blackout and the occurrences return.
public struct BlackoutSpec: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var start: DayKey
    public var end: DayKey
    public var kinds: Set<Kind>
    public var reason: String

    public init(id: UUID = UUID(), start: DayKey, end: DayKey, kinds: Set<Kind> = [], reason: String = "") {
        self.id = id
        self.start = start
        self.end = max(end, start)
        self.kinds = kinds
        self.reason = reason
    }

    public var days: ClosedRange<DayKey> { start...end }

    public func suppresses(kind: Kind, on day: DayKey) -> Bool {
        days.contains(day) && (kinds.isEmpty || kinds.contains(kind))
    }
}

public enum ExceptionKind: String, Codable, Sendable {
    case skipped
}

/// A per-occurrence override of a series. v1 supports only `skipped`.
public struct ExceptionSpec: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var seriesID: UUID
    public var day: DayKey
    public var kind: ExceptionKind

    public init(id: UUID = UUID(), seriesID: UUID, day: DayKey, kind: ExceptionKind = .skipped) {
        self.id = id
        self.seriesID = seriesID
        self.day = day
        self.kind = kind
    }
}

/// What ring math needs to know about a todo.
public struct TodoSpec: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var isDone: Bool
    /// 1 = urgent … 4 = low.
    public var priority: Int
    public var day: DayKey?
    /// Monday of the week the todo is bucketed into (when not assigned to a specific day).
    public var week: DayKey?
    public var projectID: UUID?

    public init(id: UUID = UUID(), isDone: Bool = false, priority: Int = 3, day: DayKey? = nil, week: DayKey? = nil, projectID: UUID? = nil) {
        self.id = id
        self.isDone = isDone
        self.priority = min(4, max(1, priority))
        self.day = day
        self.week = week
        self.projectID = projectID
    }
}

/// One concrete thing on the calendar: a series instance on a given day, or a one-off event.
public struct Occurrence: Hashable, Sendable, Identifiable {
    public enum Source: Hashable, Sendable {
        case series(id: UUID, day: DayKey)
        case event(id: UUID)
    }

    public var source: Source
    public var title: String
    public var kind: Kind
    public var day: DayKey
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String
    public var colorHex: String
    /// The blackout hiding this occurrence, if any. The view decides whether to show it greyed or drop it.
    public var suppressedBy: UUID?

    public init(source: Source, title: String, kind: Kind, day: DayKey, start: Date, end: Date, isAllDay: Bool = false, location: String = "", colorHex: String? = nil, suppressedBy: UUID? = nil) {
        self.source = source
        self.title = title
        self.kind = kind
        self.day = day
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.colorHex = colorHex ?? kind.colorHex
        self.suppressedBy = suppressedBy
    }

    /// Stable key, shared with notification identifiers and the EventKit mirror.
    public var id: String { Occurrence.key(for: source) }

    public var isSuppressed: Bool { suppressedBy != nil }

    public var seriesID: UUID? {
        if case .series(let id, _) = source { return id }
        return nil
    }

    public var eventID: UUID? {
        if case .event(let id) = source { return id }
        return nil
    }

    public static func key(for source: Source) -> String {
        switch source {
        case .series(let id, let day): "occ-\(id.uuidString)-\(day.rawValue)"
        case .event(let id): "evt-\(id.uuidString)"
        }
    }
}
