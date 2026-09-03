import Foundation
import SwiftData
import TimeControlCore

/// Everything the occurrence engine needs, converted from models to specs once per render.
/// Build it from `@Query` results in a view, or with `load(from:)` outside SwiftUI.
struct ScheduleSnapshot {
    var series: [SeriesSpec]
    var events: [EventSpec]
    var blackouts: [BlackoutSpec]
    var exceptions: [ExceptionSpec]

    init(series: [Series], events: [Event], blackouts: [Blackout], exceptions: [OccurrenceException]) {
        self.series = series.compactMap(\.spec)
        self.events = events.map(\.spec)
        self.blackouts = blackouts.map(\.spec)
        self.exceptions = exceptions.filter { $0.series != nil }.map(\.spec)
    }

    static let empty = ScheduleSnapshot(series: [], events: [], blackouts: [], exceptions: [])

    static func load(from context: ModelContext) -> ScheduleSnapshot {
        ScheduleSnapshot(
            series: (try? context.fetch(FetchDescriptor<Series>())) ?? [],
            events: (try? context.fetch(FetchDescriptor<Event>())) ?? [],
            blackouts: (try? context.fetch(FetchDescriptor<Blackout>())) ?? [],
            exceptions: (try? context.fetch(FetchDescriptor<OccurrenceException>())) ?? []
        )
    }

    func occurrences(in days: ClosedRange<DayKey>, includeSuppressed: Bool = false) -> [Occurrence] {
        let all = OccurrenceEngine.occurrences(in: days, series: series, events: events, blackouts: blackouts, exceptions: exceptions)
        return includeSuppressed ? all : all.filter { !$0.isSuppressed }
    }

    func occurrences(on day: DayKey, includeSuppressed: Bool = false) -> [Occurrence] {
        occurrences(in: day...day, includeSuppressed: includeSuppressed)
    }

    func next(after now: Date = Date()) -> Occurrence? {
        OccurrenceEngine.next(after: now, series: series, events: events, blackouts: blackouts, exceptions: exceptions)
    }
}

extension ModelContext {
    /// The term containing `day`; otherwise the next upcoming term; otherwise the most recent past term.
    func currentTerm(on day: DayKey = .today()) -> Term? {
        let terms = (try? fetch(FetchDescriptor<Term>(predicate: #Predicate { !$0.isArchived }))) ?? []
        if let active = terms.first(where: { $0.contains(day) }) { return active }
        if let upcoming = terms.filter({ $0.start > day }).min(by: { $0.start < $1.start }) { return upcoming }
        return terms.filter { $0.end < day }.max { $0.end < $1.end }
    }
}
