import Foundation

/// Pure arithmetic for the term's week grid: points to minutes, snapping, and what a drag proposes.
/// No SwiftUI, no models — all of it unit tested.
enum TermGridMath {
    /// Drags land on quarter hours; a plain click starts on the half hour below it.
    static let dragStep = 15
    static let clickStep = 30
    static let minimumDuration = 15
    static let defaultDuration = 90
    static let dayEnd = 24 * 60

    /// Minute of day at `y` points below the top of a column whose first rule is `firstHour`.
    static func minute(atY y: CGFloat, firstHour: Int, hourHeight: CGFloat) -> Int {
        firstHour * 60 + Int((y / hourHeight * 60).rounded(.down))
    }

    /// `minute` moved to the nearest multiple of `step`.
    static func rounded(_ minute: Int, to step: Int) -> Int {
        Int((Double(minute) / Double(step)).rounded()) * step
    }

    /// The slot a click at `minute` proposes: the half hour it falls in, `defaultDuration` long, inside the day.
    static func slot(forClickAt minute: Int) -> (start: Int, end: Int) {
        let floored = max(0, minute) / clickStep * clickStep
        let start = min(floored, dayEnd - minimumDuration)
        return (start, min(dayEnd, start + defaultDuration))
    }

    /// The slot a drag from `anchor` to `current` covers, in either direction, never shorter than the
    /// minimum and never past midnight.
    static func slot(dragFrom anchor: Int, to current: Int) -> (start: Int, end: Int) {
        let a = max(0, min(anchor, dayEnd)) / dragStep * dragStep
        let b = max(0, min(rounded(current, to: dragStep), dayEnd))
        var start = min(a, b)
        var end = max(a, b)
        if end - start < minimumDuration { end = start + minimumDuration }
        if end > dayEnd {
            end = dayEnd
            start = end - max(minimumDuration, end - start)
        }
        return (max(0, start), end)
    }

    /// `start...end` shifted by `deltaMinutes`, landing on a quarter hour, keeping its length and staying
    /// inside the day.
    static func moved(start: Int, end: Int, by deltaMinutes: Int) -> (start: Int, end: Int) {
        let duration = max(minimumDuration, end - start)
        let proposed = rounded(start + deltaMinutes, to: dragStep)
        let newStart = min(max(0, proposed), dayEnd - duration)
        return (newStart, newStart + duration)
    }

    /// `end` pulled by `deltaMinutes`, landing on a quarter hour, never shorter than the minimum after
    /// `start` and never past midnight.
    static func resized(start: Int, end: Int, by deltaMinutes: Int) -> Int {
        let proposed = rounded(end + deltaMinutes, to: dragStep)
        return min(dayEnd, max(start + minimumDuration, proposed))
    }

    /// The column index a horizontal drag of `dx` points reaches from column `from`, clamped to the grid.
    static func column(from: Int, dx: CGFloat, columnWidth: CGFloat, count: Int) -> Int {
        let delta = Int((dx / columnWidth).rounded())
        return min(max(0, from + delta), count - 1)
    }
}
