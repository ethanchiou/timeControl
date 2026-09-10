import Foundation
import SwiftData
import TimeControlCore

/// What the eye filter hides. Two independent flags: routine items (course occurrences and events
/// marked routine) and group items (events shared through a group). Empty shows everything.
nonisolated struct OccurrenceFilter: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let routine = OccurrenceFilter(rawValue: 1 << 0)
    static let group = OccurrenceFilter(rawValue: 1 << 1)

    /// Whether the filter drops this occurrence.
    func hides(_ occurrence: Occurrence) -> Bool {
        (contains(.routine) && occurrence.isRoutine) || (contains(.group) && occurrence.isGroup)
    }
}

/// Everything the occurrence engine needs, converted from models to specs once per render.
/// Build it from `@Query` results in a view, or with `load(from:)` outside SwiftUI.
///
/// Group events paint in their group's colour for this member (`SharedGroup.effectiveColorHex`), which is
/// resolved here so the engine and every view see one `colorHex`.
struct ScheduleSnapshot {
    var series: [SeriesSpec]
    var events: [EventSpec]
    var blackouts: [BlackoutSpec]
    var exceptions: [ExceptionSpec]

    init(series: [Series], events: [Event], blackouts: [Blackout], exceptions: [OccurrenceException], groups: [SharedGroup] = []) {
        let colorByGroup = Dictionary(groups.map { ($0.uuid, $0.effectiveColorHex) }, uniquingKeysWith: { first, _ in first })
        self.series = series.compactMap(\.spec)
        self.events = events.map { event in
            event.spec(groupColorHex: event.groupID.flatMap { colorByGroup[$0] })
        }
        self.blackouts = blackouts.map(\.spec)
        self.exceptions = exceptions.filter { $0.series != nil }.map(\.spec)
    }

    static let empty = ScheduleSnapshot(series: [], events: [], blackouts: [], exceptions: [])

    static func load(from context: ModelContext) -> ScheduleSnapshot {
        ScheduleSnapshot(
            series: (try? context.fetch(FetchDescriptor<Series>())) ?? [],
            events: (try? context.fetch(FetchDescriptor<Event>())) ?? [],
            blackouts: (try? context.fetch(FetchDescriptor<Blackout>())) ?? [],
            exceptions: (try? context.fetch(FetchDescriptor<OccurrenceException>())) ?? [],
            groups: (try? context.fetch(FetchDescriptor<SharedGroup>())) ?? []
        )
    }

    /// Blacked-out occurrences are dropped unless `includeSuppressed`. `hiding` is the eye filter:
    /// routine items, group items, or both.
    func occurrences(in days: ClosedRange<DayKey>, includeSuppressed: Bool = false, hiding: OccurrenceFilter = []) -> [Occurrence] {
        let all = OccurrenceEngine.occurrences(in: days, series: series, events: events, blackouts: blackouts, exceptions: exceptions)
        return all.filter { (includeSuppressed || !$0.isSuppressed) && !hiding.hides($0) }
    }

    func occurrences(on day: DayKey, includeSuppressed: Bool = false, hiding: OccurrenceFilter = []) -> [Occurrence] {
        occurrences(in: day...day, includeSuppressed: includeSuppressed, hiding: hiding)
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
