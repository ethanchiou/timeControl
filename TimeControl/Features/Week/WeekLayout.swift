import Foundation

/// One thing to place in a day column. Minutes are since local midnight.
struct LayoutItem: Equatable {
    let id: String
    let startMinute: Int
    let endMinute: Int
}

/// Where `WeekLayout.pack` put an item: `column` of `columnCount` equal shares of the column's width.
struct LayoutSlot: Equatable {
    let id: String
    let column: Int
    let columnCount: Int
}

/// Pure geometry for the week grid: no SwiftUI, no models, no dates — all of it unit tested.
enum WeekLayout {
    /// Hours shown whether or not anything is scheduled in them.
    static let defaultHours: ClosedRange<Int> = 7...22

    /// Classic interval partitioning. Items sorted by start (longer first) fall into clusters of
    /// transitively overlapping items; inside a cluster each item takes the lowest column free at its
    /// start minute, and every item of the cluster reports the cluster's column count so the blocks
    /// split the width evenly. Touching intervals (`end == start`) do not overlap.
    ///
    /// Slots come back in the order the items were passed in.
    static func pack(_ items: [LayoutItem]) -> [LayoutSlot] {
        let ordered = items.sorted { a, b in
            if a.startMinute != b.startMinute { return a.startMinute < b.startMinute }
            if a.endMinute != b.endMinute { return a.endMinute > b.endMinute }
            return a.id < b.id
        }

        var placed: [String: LayoutSlot] = [:]
        var cluster: [(id: String, column: Int)] = []
        var columnEnds: [Int] = []
        var clusterEnd = Int.min

        func flush() {
            let count = max(1, columnEnds.count)
            for item in cluster {
                placed[item.id] = LayoutSlot(id: item.id, column: item.column, columnCount: count)
            }
            cluster.removeAll()
            columnEnds.removeAll()
            clusterEnd = Int.min
        }

        for item in ordered {
            // Sorted by start, so an item starting at or after every end so far opens a new cluster.
            if !cluster.isEmpty, item.startMinute >= clusterEnd { flush() }
            let column: Int
            if let free = columnEnds.firstIndex(where: { $0 <= item.startMinute }) {
                column = free
                columnEnds[free] = max(columnEnds[free], item.endMinute)
            } else {
                column = columnEnds.count
                columnEnds.append(item.endMinute)
            }
            cluster.append((item.id, column))
            clusterEnd = max(clusterEnd, item.endMinute)
        }
        flush()

        return items.compactMap { placed[$0.id] }
    }

    /// `base`, widened to whole hours around anything scheduled outside it.
    static func hourRange(covering items: [LayoutItem], base: ClosedRange<Int> = defaultHours) -> ClosedRange<Int> {
        var low = base.lowerBound
        var high = base.upperBound
        for item in items {
            low = min(low, item.startMinute / 60)
            high = max(high, (item.endMinute + 59) / 60)
        }
        low = max(0, low)
        high = min(24, max(high, low + 1))
        return low...high
    }
}
