import Testing
@testable import TimeControl

@Suite struct WeekLayoutTests {
    /// 9:00 is minute 540.
    func item(_ id: String, _ start: Int, _ end: Int) -> LayoutItem {
        LayoutItem(id: id, startMinute: start, endMinute: end)
    }

    @Test func nonOverlappingItemsEachTakeTheWholeColumn() {
        let items = [item("a", 540, 600), item("b", 660, 720), item("c", 780, 840)]
        let slots = WeekLayout.pack(items)
        #expect(slots.map(\.id) == ["a", "b", "c"])
        #expect(slots.allSatisfy { $0.column == 0 && $0.columnCount == 1 })
    }

    @Test func overlappingItemsSplitTheColumn() {
        let slots = WeekLayout.pack([item("a", 540, 660), item("b", 600, 720)])
        #expect(slots == [
            LayoutSlot(id: "a", column: 0, columnCount: 2),
            LayoutSlot(id: "b", column: 1, columnCount: 2),
        ])
    }

    @Test func chainedOverlapReusesTheFreedColumn() {
        // A–B overlap and B–C overlap, but A and C only touch: one cluster, two columns, C back in column 0.
        let slots = WeekLayout.pack([item("a", 540, 600), item("b", 570, 630), item("c", 600, 660)])
        #expect(slots == [
            LayoutSlot(id: "a", column: 0, columnCount: 2),
            LayoutSlot(id: "b", column: 1, columnCount: 2),
            LayoutSlot(id: "c", column: 0, columnCount: 2),
        ])
    }

    @Test func touchingIntervalsDoNotOverlap() {
        let slots = WeekLayout.pack([item("a", 540, 600), item("b", 600, 660)])
        #expect(slots == [
            LayoutSlot(id: "a", column: 0, columnCount: 1),
            LayoutSlot(id: "b", column: 0, columnCount: 1),
        ])
    }

    @Test func threeWayOverlapUsesThreeColumns() {
        let slots = WeekLayout.pack([item("a", 540, 720), item("b", 570, 690), item("c", 600, 660)])
        #expect(slots.map(\.column) == [0, 1, 2])
        #expect(slots.allSatisfy { $0.columnCount == 3 })
    }

    @Test func packReturnsSlotsInInputOrder() {
        let slots = WeekLayout.pack([item("late", 600, 660), item("early", 540, 630)])
        #expect(slots.map(\.id) == ["late", "early"])
        #expect(slots.map(\.column) == [1, 0])
    }

    @Test func emptyInputPacksToNothing() {
        #expect(WeekLayout.pack([]).isEmpty)
    }

    @Test func hourRangeFallsBackToTheDefaultWindow() {
        #expect(WeekLayout.hourRange(covering: []) == 7...22)
        #expect(WeekLayout.hourRange(covering: [item("a", 540, 600)]) == 7...22)
    }

    @Test func hourRangeExtendsToWholeHoursAroundOutliers() {
        let range = WeekLayout.hourRange(covering: [item("dawn", 380, 420), item("night", 1330, 1390)])
        #expect(range == 6...24)
    }
}
