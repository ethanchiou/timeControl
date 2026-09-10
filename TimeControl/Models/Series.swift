import Foundation
import SwiftData
import TimeControlCore

extension SchemaV2 {
    /// A recurring course/meeting inside a term. Occurs in term week `w` iff
    /// `startWeek ≤ w ≤ endWeek && (w − startWeek) % intervalWeeks == 0`, on each weekday in `weekdaysMask`.
    @Model
    final class Series {
        var uuid: UUID = UUID()
        var title: String = ""
        var kindRaw: String = Kind.course.rawValue
        var weekdaysMask: Int = 0
        /// Minutes since local midnight.
        var startMinute: Int = 540
        var endMinute: Int = 600
        /// 1 = weekly, 2 = biweekly.
        var intervalWeeks: Int = 1
        /// 1-based, term-relative, inclusive.
        var startWeek: Int = 1
        var endWeek: Int = 1
        var location: String = ""
        var notes: String = ""
        var colorHex: String?
        var createdAt: Date = Date()
        /// The server's `updated_at` for the state last pushed or pulled; nil = never synced.
        var syncedAt: Date?

        var term: Term?

        @Relationship(deleteRule: .cascade, inverse: \OccurrenceException.series)
        var exceptions: [OccurrenceException]?

        init(
            title: String,
            kind: Kind = .course,
            weekdays: Set<Weekday>,
            startMinute: Int,
            endMinute: Int,
            intervalWeeks: Int = 1,
            startWeek: Int = 1,
            endWeek: Int,
            location: String = "",
            notes: String = ""
        ) {
            self.title = title
            self.kindRaw = kind.rawValue
            self.weekdaysMask = Weekday.mask(of: weekdays)
            self.startMinute = startMinute
            self.endMinute = max(endMinute, startMinute + 5)
            self.intervalWeeks = max(1, intervalWeeks)
            self.startWeek = max(1, startWeek)
            self.endWeek = max(self.startWeek, endWeek)
            self.location = location
            self.notes = notes
        }
    }
}

extension Series {
    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .course }
        set { kindRaw = newValue.rawValue }
    }

    var weekdays: Set<Weekday> {
        get { Weekday.set(fromMask: weekdaysMask) }
        set { weekdaysMask = Weekday.mask(of: newValue) }
    }

    var sortedWeekdays: [Weekday] { weekdays.sorted() }

    var isBiweekly: Bool { intervalWeeks == 2 }

    /// Nil when the series has no term (should not happen through the UI).
    var spec: SeriesSpec? {
        guard let term else { return nil }
        return SeriesSpec(
            id: uuid,
            title: title,
            kind: kind,
            term: term.spec,
            weekdays: weekdays,
            startMinute: startMinute,
            endMinute: endMinute,
            intervalWeeks: intervalWeeks,
            startWeek: startWeek,
            endWeek: endWeek,
            location: location,
            colorHex: colorHex
        )
    }

    var exceptionSpecs: [ExceptionSpec] {
        (exceptions ?? []).map(\.spec)
    }

    /// "Mon/Wed 10:00–11:30" style summary.
    var scheduleSummary: String {
        let days = sortedWeekdays.map(\.shortName).joined(separator: "/")
        return "\(days) \(WeekMath.timeLabel(minute: startMinute))–\(WeekMath.timeLabel(minute: endMinute))"
    }
}
