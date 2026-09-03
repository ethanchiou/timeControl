import Foundation
import Testing
@testable import TimeControlCore

@Suite struct RingMathTests {
    func d(_ m: Int, _ day: Int) -> DayKey { DayKey(year: 2026, month: m, day: day) }

    @Test func emptySetGivesEmptyProgress() {
        let p = RingMath.progress(of: [] as [TodoSpec])
        #expect(p == .empty)
        #expect(p.isEmpty)
        #expect(p.fraction == 0)
    }

    @Test func dailyCountsOnlyExactDay() {
        let mon = d(9, 7)
        let todos = [
            TodoSpec(isDone: true, day: mon),
            TodoSpec(isDone: false, day: mon),
            TodoSpec(isDone: false, day: d(9, 8)),
            TodoSpec(isDone: false, week: mon)
        ]
        let p = RingMath.daily(todos, on: mon)
        #expect(p.total == 2)
        #expect(p.done == 1)
    }

    @Test func weeklyCountsWeekBucketAndDayBucketButIgnoresAdjacentWeeks() {
        // Week of Mon Sep 7 - Sun Sep 13.
        let monday = d(9, 7)
        let todos = [
            TodoSpec(isDone: true, week: monday),          // week-bucketed, in week
            TodoSpec(isDone: false, day: d(9, 9)),          // day-bucketed, in week
            TodoSpec(isDone: true, day: d(9, 13)),          // day-bucketed, last day of week
            TodoSpec(isDone: false, day: d(9, 14)),         // next week's Monday, excluded
            TodoSpec(isDone: false, week: d(9, 14)),        // next week's bucket, excluded
            TodoSpec(isDone: false, day: d(9, 6))           // previous week's Sunday, excluded
        ]
        let p = RingMath.weekly(todos, weekOf: monday)
        #expect(p.total == 3)
        #expect(p.done == 2)
    }

    @Test func weeklyNormalisesGivenDayToItsMonday() {
        let thursday = d(9, 10)
        let monday = d(9, 7)
        let todos = [
            TodoSpec(isDone: false, week: monday),
            TodoSpec(isDone: false, day: d(9, 12))
        ]
        let p = RingMath.weekly(todos, weekOf: thursday)
        #expect(p.total == 2)
    }

    @Test func projectFiltersByProjectID() {
        let projectA = UUID()
        let projectB = UUID()
        let todos = [
            TodoSpec(isDone: true, projectID: projectA),
            TodoSpec(isDone: false, projectID: projectA),
            TodoSpec(isDone: false, projectID: projectB),
            TodoSpec(isDone: false, projectID: nil)
        ]
        let p = RingMath.project(todos, id: projectA)
        #expect(p.total == 2)
        #expect(p.done == 1)
    }

    @Test func fractionIsCompleteAndIsEmpty() {
        #expect(RingProgress(done: 0, total: 0).fraction == 0)
        #expect(RingProgress(done: 0, total: 0).isEmpty)
        #expect(!RingProgress(done: 0, total: 0).isComplete)

        let half = RingProgress(done: 1, total: 2)
        #expect(half.fraction == 0.5)
        #expect(!half.isComplete)
        #expect(!half.isEmpty)
        #expect(half.remaining == 1)

        let full = RingProgress(done: 3, total: 3)
        #expect(full.isComplete)
        #expect(full.remaining == 0)
    }

    @Test func clampingKeepsDoneWithinBounds() {
        #expect(RingProgress(done: 5, total: 3).done == 3)
        #expect(RingProgress(done: -1, total: 3).done == 0)
        #expect(RingProgress(done: 2, total: -4).total == 0)
        #expect(RingProgress(done: 2, total: -4).done == 0)
    }

    @Test func listOrderPutsOpenBeforeDoneThenByPriority() {
        let openLow = TodoSpec(isDone: false, priority: 4)
        let openHigh = TodoSpec(isDone: false, priority: 1)
        let doneHigh = TodoSpec(isDone: true, priority: 1)

        #expect(RingMath.listOrder(openHigh, openLow))
        #expect(!RingMath.listOrder(openLow, openHigh))
        #expect(RingMath.listOrder(openLow, doneHigh))
        #expect(!RingMath.listOrder(doneHigh, openLow))
        #expect(RingMath.listOrder(openHigh, doneHigh))
    }
}
