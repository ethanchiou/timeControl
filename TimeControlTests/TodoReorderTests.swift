import Foundation
import SwiftData
import Testing
import TimeControlCore
@testable import TimeControl

/// End-to-end for the drag handle: the array arithmetic lives in `TodoOrderingTests`, this checks the
/// order a drag produces actually survives `listOrder`, which is where a reorder feature usually dies.
@MainActor
@Suite struct TodoReorderTests {
    struct Store {
        let container: ModelContainer
        var ctx: ModelContext { container.mainContext }
    }

    private func makeStore() throws -> Store {
        Store(container: try ModelContainerFactory.make(inMemory: true))
    }

    /// Three todos whose priorities alone would sort them urgent-first.
    private func seed(_ ctx: ModelContext) -> (urgent: TodoItem, normal: TodoItem, low: TodoItem) {
        let day = DayKey(year: 2026, month: 9, day: 3)
        let urgent = TodoItem(title: "Urgent", priority: 1, day: day)
        let normal = TodoItem(title: "Normal", priority: 3, day: day)
        let low = TodoItem(title: "Low", priority: 4, day: day)
        for todo in [urgent, normal, low] { ctx.insert(todo) }
        return (urgent, normal, low)
    }

    private func titles(_ todos: [TodoItem]) -> [String] {
        todos.sorted(by: TodoItem.listOrder).map(\.title)
    }

    @Test func priorityStillOrdersAListNobodyHasDragged() throws {
        let store = try makeStore()
        let (urgent, normal, low) = seed(store.ctx)
        // Everything starts at sortOrder 0, so the ties fall through to priority exactly as before.
        #expect([urgent, normal, low].allSatisfy { $0.sortOrder == 0 })
        #expect(titles([low, normal, urgent]) == ["Urgent", "Normal", "Low"])
    }

    @Test func aLowPriorityTodoDraggedToTheTopStaysThere() throws {
        let store = try makeStore()
        let (urgent, normal, low) = seed(store.ctx)
        let list = [urgent, normal, low].sorted(by: TodoItem.listOrder)

        TodoItem.reorder(low, before: urgent, in: list)

        // This is the whole point: without manual order outranking priority the P1 would snap back on top.
        #expect(titles(list) == ["Low", "Urgent", "Normal"])
    }

    @Test func draggingToTheEndPutsItLast() throws {
        let store = try makeStore()
        let (urgent, normal, low) = seed(store.ctx)
        let list = [urgent, normal, low].sorted(by: TodoItem.listOrder)

        TodoItem.reorder(urgent, before: nil, in: list)

        #expect(titles(list) == ["Normal", "Low", "Urgent"])
    }

    @Test func aReorderSurvivesAnotherReorder() throws {
        let store = try makeStore()
        let (urgent, normal, low) = seed(store.ctx)
        var list = [urgent, normal, low].sorted(by: TodoItem.listOrder)

        TodoItem.reorder(low, before: urgent, in: list)
        list = list.sorted(by: TodoItem.listOrder)
        TodoItem.reorder(normal, before: low, in: list)

        #expect(titles(list) == ["Normal", "Low", "Urgent"])
        // Renumbered contiguously, so the next drag has clean indices to work from.
        #expect(Set(list.map(\.sortOrder)) == [0, 1, 2])
    }

    @Test func completedTodosStaySunkNoMatterTheOrder() throws {
        let store = try makeStore()
        let (urgent, normal, low) = seed(store.ctx)
        let list = [urgent, normal, low].sorted(by: TodoItem.listOrder)
        normal.setDone(true)

        // Drag the finished one to the very top; done still sinks, because that ranks above manual order.
        TodoItem.reorder(normal, before: urgent, in: list)

        #expect(titles(list) == ["Urgent", "Low", "Normal"])
    }

    @Test func aTodoDraggedInFromAnotherBucketJoinsTheOrder() throws {
        let store = try makeStore()
        let (urgent, normal, low) = seed(store.ctx)
        let incoming = TodoItem(title: "From backlog", priority: 2)
        store.ctx.insert(incoming)
        let list = [urgent, normal, low].sorted(by: TodoItem.listOrder)

        // The dragged todo is not yet in this bucket's array — it must still land where it was dropped.
        TodoItem.reorder(incoming, before: normal, in: list)

        #expect(titles(list + [incoming]) == ["Urgent", "From backlog", "Normal", "Low"])
    }
}
