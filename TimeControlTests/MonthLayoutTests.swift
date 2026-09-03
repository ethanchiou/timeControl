import Testing
import TimeControlCore
@testable import TimeControl

@Suite struct MonthLayoutTests {
    @Test func rowsSplitTheSpanIntoWeeksOfSeven() {
        let grid = DayKey(year: 2026, month: 9, day: 17).monthGrid
        let rows = MonthLayout.rows(in: grid)
        #expect(rows.count == 5)
        #expect(rows.allSatisfy { $0.count == 7 })
        #expect(rows.first?.first == grid.lowerBound)
        #expect(rows.last?.last == grid.upperBound)
        #expect(rows.allSatisfy { $0.first?.weekday == .monday && $0.last?.weekday == .sunday })
        // Contiguous, no gaps or repeats.
        #expect(rows.flatMap { $0 } == Array(grid))
    }

    @Test func rowsCoverASixWeekMonth() {
        // August 2026 starts on a Saturday and needs six rows.
        let rows = MonthLayout.rows(in: DayKey(year: 2026, month: 8, day: 15).monthGrid)
        #expect(rows.count == 6)
        #expect(rows.allSatisfy { $0.count == 7 })
    }

    @Test func capacityCountsWholePillsBelowTheDateLine() {
        // 100pt cell, 20pt date line, 17pt pills, 2pt gaps: 80 / 19 → 4.
        #expect(MonthLayout.capacity(cellHeight: 100, dateHeight: 20, pillHeight: 17, spacing: 2) == 4)
        // Exactly three pills' worth and no more.
        #expect(MonthLayout.capacity(cellHeight: 20 + 17 * 3 + 2 * 2, dateHeight: 20, pillHeight: 17, spacing: 2) == 3)
        // A cell with no room below the date line holds nothing, and never reports a negative.
        #expect(MonthLayout.capacity(cellHeight: 20, dateHeight: 20, pillHeight: 17, spacing: 2) == 0)
        #expect(MonthLayout.capacity(cellHeight: 5, dateHeight: 20, pillHeight: 17, spacing: 2) == 0)
        #expect(MonthLayout.capacity(cellHeight: 100, dateHeight: 20, pillHeight: 0, spacing: 2) == 0)
    }

    @Test func fitShowsEverythingWhenItFits() {
        #expect(MonthLayout.fit(count: 0, capacity: 4) == (0, 0))
        #expect(MonthLayout.fit(count: 3, capacity: 4) == (3, 0))
        #expect(MonthLayout.fit(count: 4, capacity: 4) == (4, 0))
    }

    @Test func fitSpendsOneSlotOnTheOverflowChip() {
        // 6 items in 4 slots: three pills and a "+3 more".
        let split = MonthLayout.fit(count: 6, capacity: 4)
        #expect(split == (3, 3))
        #expect(split.shown + split.hidden == 6)
        // The chip never hides fewer than two, so it always earns its slot.
        for count in 5...20 {
            let s = MonthLayout.fit(count: count, capacity: 4)
            #expect(s.shown + s.hidden == count, "\(count)")
            #expect(s.hidden >= 2, "\(count)")
        }
    }

    @Test func fitDegradesWhenThereIsNoRoom() {
        #expect(MonthLayout.fit(count: 5, capacity: 0) == (0, 5))
        #expect(MonthLayout.fit(count: 5, capacity: 1) == (0, 5))
        #expect(MonthLayout.fit(count: 1, capacity: 1) == (1, 0))
    }

    @Test func shareKeepsASlotForTasksOnABusyDay() {
        // Five courses and two tasks in four slots: tasks still get one, so the day does not read
        // as "nothing due".
        let split = MonthLayout.share(slots: 4, occurrences: 5, todos: 2)
        #expect(split == (3, 1))
        #expect(split.occurrences + split.todos == 4)
    }

    @Test func shareGivesEverythingItsSlotWhenThereIsRoom() {
        #expect(MonthLayout.share(slots: 4, occurrences: 2, todos: 1) == (2, 1))
        #expect(MonthLayout.share(slots: 4, occurrences: 2, todos: 5) == (2, 2))
        #expect(MonthLayout.share(slots: 4, occurrences: 0, todos: 3) == (0, 3))
        #expect(MonthLayout.share(slots: 4, occurrences: 3, todos: 0) == (3, 0))
    }

    @Test func shareDegradesWhenThereIsNoRoom() {
        #expect(MonthLayout.share(slots: 0, occurrences: 5, todos: 5) == (0, 0))
        // One slot cannot show both; the timed item wins.
        #expect(MonthLayout.share(slots: 1, occurrences: 5, todos: 5) == (1, 0))
        #expect(MonthLayout.share(slots: 1, occurrences: 0, todos: 5) == (0, 1))
    }

    @Test func shareNeverOverfillsOrLosesASlot() {
        for slots in 0...8 {
            for occurrences in 0...8 {
                for todos in 0...8 {
                    let s = MonthLayout.share(slots: slots, occurrences: occurrences, todos: todos)
                    #expect(s.occurrences >= 0 && s.todos >= 0, "\(slots)/\(occurrences)/\(todos)")
                    #expect(s.occurrences <= occurrences && s.todos <= todos, "\(slots)/\(occurrences)/\(todos)")
                    #expect(s.occurrences + s.todos <= slots, "\(slots)/\(occurrences)/\(todos)")
                    // No slot left idle while something still wants it.
                    #expect(s.occurrences + s.todos == min(slots, occurrences + todos), "\(slots)/\(occurrences)/\(todos)")
                }
            }
        }
    }
}
