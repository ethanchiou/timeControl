import Foundation
import SwiftData
import Testing
import TimeControlCore
@testable import TimeControl

@MainActor
@Suite(.serialized) struct RolloverServiceTests {
    /// Holds the container: a `ModelContext` whose container has been deallocated traps silently on the next insert.
    struct Store {
        let container: ModelContainer
        var ctx: ModelContext { container.mainContext }
    }

    func makeStore() throws -> Store {
        Store(container: try ModelContainerFactory.make(inMemory: true))
    }

    /// Wednesday, 9 September 2026.
    let today = DayKey(year: 2026, month: 9, day: 9)

    @Test func isEnabledDefaultsToTrueWhenUnset() {
        defer { RolloverService.isEnabled = true }
        UserDefaults.standard.removeObject(forKey: RolloverService.enabledKey)
        #expect(RolloverService.isEnabled)
        RolloverService.isEnabled = false
        #expect(!RolloverService.isEnabled)
    }

    @Test func movesOpenTodosFromPastDaysOntoToday() throws {
        RolloverService.isEnabled = true
        defer { RolloverService.isEnabled = true }
        let store = try makeStore()
        let ctx = store.ctx

        let yesterday = TodoItem(title: "Yesterday open", day: today - 1)
        let older = TodoItem(title: "Older open", day: today - 8)
        let yesterdayDone = TodoItem(title: "Yesterday done", day: today - 1)
        let onToday = TodoItem(title: "Today", day: today)
        let tomorrow = TodoItem(title: "Tomorrow", day: today + 1)
        for todo in [yesterday, older, yesterdayDone, onToday, tomorrow] { ctx.insert(todo) }
        yesterdayDone.setDone(true)
        try ctx.save()

        let moved = RolloverService.run(in: ctx, today: today)

        #expect(Set(moved.map(\.title)) == ["Yesterday open", "Older open"])
        #expect(yesterday.day == today)
        #expect(older.day == today)
        #expect(yesterdayDone.day == today - 1)
        #expect(onToday.day == today)
        #expect(tomorrow.day == today + 1)
    }

    @Test func leavesWeekBucketsAlone() throws {
        RolloverService.isEnabled = true
        defer { RolloverService.isEnabled = true }
        let store = try makeStore()
        let ctx = store.ctx

        let weekOnly = TodoItem(title: "Week only", week: today)
        let pastWeekOnly = TodoItem(title: "Past week only", week: today - 7)
        let dayAndWeek = TodoItem(title: "Day and week", day: today - 2, week: today - 9)
        for todo in [weekOnly, pastWeekOnly, dayAndWeek] { ctx.insert(todo) }
        try ctx.save()
        let staleWeek = (today - 9).weekStart

        let moved = RolloverService.run(in: ctx, today: today)

        #expect(moved.map(\.title) == ["Day and week"])
        #expect(weekOnly.day == nil && weekOnly.week == today.weekStart)
        #expect(pastWeekOnly.day == nil && pastWeekOnly.week == (today - 7).weekStart)
        // The day moves; the week bucket the todo was filed under is left exactly as it was.
        #expect(dayAndWeek.day == today)
        #expect(dayAndWeek.week == staleWeek)
    }

    @Test func isIdempotent() throws {
        RolloverService.isEnabled = true
        defer { RolloverService.isEnabled = true }
        let store = try makeStore()
        let ctx = store.ctx
        ctx.insert(TodoItem(title: "A", day: today - 1))
        ctx.insert(TodoItem(title: "B", day: today - 3))
        try ctx.save()

        #expect(RolloverService.run(in: ctx, today: today).count == 2)
        #expect(RolloverService.run(in: ctx, today: today).isEmpty)
    }

    @Test func movesNothingWhenDisabled() throws {
        defer { RolloverService.isEnabled = true }
        RolloverService.isEnabled = false
        let store = try makeStore()
        let ctx = store.ctx
        let stale = TodoItem(title: "Stale", day: today - 1)
        ctx.insert(stale)
        try ctx.save()

        #expect(RolloverService.run(in: ctx, today: today).isEmpty)
        #expect(stale.day == today - 1)
    }
}
