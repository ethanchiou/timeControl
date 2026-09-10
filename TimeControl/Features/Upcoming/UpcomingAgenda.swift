import Foundation
import TimeControlCore

/// The pure part of the Upcoming list — which days a window covers, what is still to come, and how it
/// groups by day. No SwiftUI, no models — unit tested the way `MonthLayout` is.
enum UpcomingAgenda {
    struct DayGroup: Identifiable, Equatable {
        let day: DayKey
        let occurrences: [Occurrence]
        var id: DayKey { day }
    }

    /// The rolling window from `today`: the rest of today, the next seven days or the next thirty.
    static func days(for scale: CalendarScale, from today: DayKey) -> ClosedRange<DayKey> {
        switch scale {
        case .day: today...today
        case .week: today...(today + 6)
        case .month: today...(today + 29)
        }
    }

    /// What has not happened yet at `now`: everything on a later day, and today's items that have not
    /// ended — an all-day item stands for the whole day. Anything earlier, or blacked out, is gone.
    static func pending(_ occurrences: [Occurrence], now: Date, today: DayKey) -> [Occurrence] {
        occurrences.filter { occurrence in
            guard !occurrence.isSuppressed, occurrence.day >= today else { return false }
            return occurrence.day > today || occurrence.isAllDay || occurrence.end > now
        }
    }

    /// Grouped by day, days ascending, each day in display order.
    static func groups(_ occurrences: [Occurrence]) -> [DayGroup] {
        Dictionary(grouping: occurrences, by: \.day)
            .sorted { $0.key < $1.key }
            .map { DayGroup(day: $0.key, occurrences: $0.value.sorted(by: Occurrence.displayOrder)) }
    }

    /// "Today" and "Tomorrow" by name; any other day goes by its date.
    static func relativeName(_ day: DayKey, today: DayKey) -> String? {
        switch day - today {
        case 0: "Today"
        case 1: "Tomorrow"
        default: nil
        }
    }
}
