import Foundation

/// Expands recurring series and one-off events into concrete `Occurrence`s for a range of days.
///
/// Pipeline: series → weekday/week filter → drop skipped exceptions → mark blackouts → merge events → sort.
/// Nothing is materialized; call this for whatever window a view needs (a day, a week, the next 60 days).
/// Blackouts apply to recurring series only; one-off events are explicit and are never suppressed.
public enum OccurrenceEngine {
    public static func occurrences(
        in days: ClosedRange<DayKey>,
        series: [SeriesSpec],
        events: [EventSpec] = [],
        blackouts: [BlackoutSpec] = [],
        exceptions: [ExceptionSpec] = [],
        calendar: Calendar = .app
    ) -> [Occurrence] {
        var result: [Occurrence] = []

        let skipped = Set(
            exceptions.lazy.filter { $0.kind == .skipped }.map { SkipKey(seriesID: $0.seriesID, day: $0.day) }
        )

        for day in days {
            for s in series where s.occurs(on: day) {
                if skipped.contains(SkipKey(seriesID: s.id, day: day)) { continue }
                let blackout = blackouts.first { $0.suppresses(kind: s.kind, on: day) }
                result.append(
                    Occurrence(
                        source: .series(id: s.id, day: day),
                        title: s.title,
                        kind: s.kind,
                        day: day,
                        start: WeekMath.instant(day: day, minute: s.startMinute, calendar: calendar),
                        end: WeekMath.instant(day: day, minute: s.endMinute, calendar: calendar),
                        location: s.location,
                        colorHex: s.colorHex,
                        suppressedBy: blackout?.id,
                        isRoutine: true
                    )
                )
            }
        }

        for e in events {
            let day = DayKey(e.start, calendar: calendar)
            guard days.contains(day) else { continue }
            result.append(
                Occurrence(
                    source: .event(id: e.id),
                    title: e.title,
                    kind: e.kind,
                    day: day,
                    start: e.start,
                    end: e.end,
                    isAllDay: e.isAllDay,
                    location: e.location,
                    colorHex: e.colorHex,
                    isRoutine: e.isRoutine,
                    groupID: e.groupID
                )
            )
        }

        result.sort(by: Occurrence.displayOrder)
        return result
    }

    public static func occurrences(
        on day: DayKey,
        series: [SeriesSpec],
        events: [EventSpec] = [],
        blackouts: [BlackoutSpec] = [],
        exceptions: [ExceptionSpec] = [],
        calendar: Calendar = .app
    ) -> [Occurrence] {
        occurrences(in: day...day, series: series, events: events, blackouts: blackouts, exceptions: exceptions, calendar: calendar)
    }

    /// The first non-suppressed timed occurrence that ends after `now`, looking at most `lookaheadDays` ahead.
    public static func next(
        after now: Date,
        lookaheadDays: Int = 14,
        series: [SeriesSpec],
        events: [EventSpec] = [],
        blackouts: [BlackoutSpec] = [],
        exceptions: [ExceptionSpec] = [],
        calendar: Calendar = .app
    ) -> Occurrence? {
        let today = DayKey(now, calendar: calendar)
        let all = occurrences(
            in: today...(today + max(0, lookaheadDays)),
            series: series, events: events, blackouts: blackouts, exceptions: exceptions, calendar: calendar
        )
        return all.first { !$0.isSuppressed && !$0.isAllDay && $0.end > now }
    }

    private struct SkipKey: Hashable {
        let seriesID: UUID
        let day: DayKey
    }
}

extension Occurrence {
    /// Day, then all-day items first, then start time, then title. Stable across calls.
    public static func displayOrder(_ a: Occurrence, _ b: Occurrence) -> Bool {
        if a.day != b.day { return a.day < b.day }
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        if a.start != b.start { return a.start < b.start }
        if a.title != b.title { return a.title < b.title }
        return a.id < b.id
    }
}
