import Foundation
import TimeControlCore

/// Pure geometry for the month grid: no SwiftUI, no models, no dates beyond `DayKey` — all of it
/// unit tested, the same way `WeekLayout` is.
enum MonthLayout {
    /// A whole-weeks span split into rows of seven days. `days` comes from `DayKey.monthGrid`, which
    /// guarantees the multiple of seven.
    static func rows(in days: ClosedRange<DayKey>) -> [[DayKey]] {
        stride(from: days.lowerBound.rawValue, through: days.upperBound.rawValue, by: 7).map { start in
            (0..<7).map { DayKey(rawValue: start + $0) }
        }
    }

    /// How many pills fit in a cell of `height`, below its date line.
    static func capacity(cellHeight: CGFloat, dateHeight: CGFloat, pillHeight: CGFloat, spacing: CGFloat) -> Int {
        let free = cellHeight - dateHeight
        guard free > 0, pillHeight > 0 else { return 0 }
        return max(0, Int((free + spacing) / (pillHeight + spacing)))
    }

    /// How a cell splits `count` items across `capacity` slots. When they do not all fit, one slot
    /// goes to the "+N more" chip — so a cell never spends a slot hiding a single item.
    static func fit(count: Int, capacity: Int) -> (shown: Int, hidden: Int) {
        guard capacity > 0 else { return (0, count) }
        if count <= capacity { return (count, 0) }
        let shown = capacity - 1
        return (shown, count - shown)
    }

    /// How `slots` are dealt between the occurrences in a cell and the tasks under them.
    ///
    /// Occurrences come first, but tasks keep a slot whenever there is more than one to give: a day
    /// with five courses on it would otherwise never show that something is due, which is the whole
    /// point of putting tasks on the calendar.
    static func share(slots: Int, occurrences: Int, todos: Int) -> (occurrences: Int, todos: Int) {
        guard slots > 0 else { return (0, 0) }
        if todos == 0 { return (min(slots, occurrences), 0) }
        if occurrences == 0 { return (0, min(slots, todos)) }
        if slots == 1 { return (1, 0) }
        let forTodos = min(todos, max(1, slots - occurrences))
        return (min(occurrences, slots - forTodos), forTodos)
    }
}
