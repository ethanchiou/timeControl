import Foundation
import SwiftData
import TimeControlCore

extension SchemaV1 {
    /// A semester. Week 1 starts on the Monday of the week containing `start`.
    @Model
    final class Term {
        var uuid: UUID = UUID()
        var name: String = ""
        var startDayKey: Int = 0
        var endDayKey: Int = 0
        var isArchived: Bool = false
        var createdAt: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \Series.term)
        var series: [Series]?

        @Relationship(deleteRule: .cascade, inverse: \Blackout.term)
        var blackouts: [Blackout]?

        init(name: String, start: DayKey, end: DayKey) {
            self.name = name
            self.startDayKey = start.rawValue
            self.endDayKey = max(end, start).rawValue
        }
    }
}

extension Term {
    var start: DayKey {
        get { DayKey(rawValue: startDayKey) }
        set { startDayKey = newValue.rawValue }
    }

    var end: DayKey {
        get { DayKey(rawValue: endDayKey) }
        set { endDayKey = newValue.rawValue }
    }

    var weeks: TermWeeks { TermWeeks(termStart: start, termEnd: end) }
    var weekCount: Int { weeks.weekCount }
    var spec: TermSpec { TermSpec(id: uuid, name: name, start: start, end: end) }

    func contains(_ day: DayKey) -> Bool { day >= start && day <= end }
    func weekNumber(of day: DayKey) -> Int? { weeks.weekNumber(of: day) }

    /// Courses sorted by first weekday, then start time, then title.
    var sortedSeries: [Series] {
        (series ?? []).sorted { a, b in
            let wa = a.weekdays.min()?.rawValue ?? 7
            let wb = b.weekdays.min()?.rawValue ?? 7
            if wa != wb { return wa < wb }
            if a.startMinute != b.startMinute { return a.startMinute < b.startMinute }
            return a.title < b.title
        }
    }

    var sortedBlackouts: [Blackout] {
        (blackouts ?? []).sorted { ($0.startDayKey, $0.reason) < ($1.startDayKey, $1.reason) }
    }
}
