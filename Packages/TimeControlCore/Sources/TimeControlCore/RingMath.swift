import Foundation

/// Done/total counts backing a progress ring.
public struct RingProgress: Hashable, Sendable {
    public let done: Int
    public let total: Int

    /// Clamps `done` into `0...total`. `total` is floored at 0.
    public init(done: Int, total: Int) {
        let clampedTotal = max(0, total)
        self.total = clampedTotal
        self.done = min(max(0, done), clampedTotal)
    }

    /// Fraction complete, `0` when `total == 0`.
    public var fraction: Double {
        total == 0 ? 0 : Double(done) / Double(total)
    }

    public var isComplete: Bool { total > 0 && done == total }

    public var isEmpty: Bool { total == 0 }

    public var remaining: Int { total - done }

    public static let empty = RingProgress(done: 0, total: 0)
}

/// Progress-ring aggregation for todos, bucketed by day, week, or project.
public enum RingMath {
    /// Todos whose `day == day`.
    public static func daily(_ todos: some Sequence<TodoSpec>, on day: DayKey) -> RingProgress {
        progress(of: todos.filter { $0.day == day })
    }

    /// Todos whose `week == monday` plus todos whose `day` falls in that week.
    /// `day` may be any day in the week; it is normalised to its Monday.
    public static func weekly(_ todos: some Sequence<TodoSpec>, weekOf day: DayKey) -> RingProgress {
        let monday = day.weekStart
        let range = monday.week
        return progress(of: todos.filter { todo in
            if todo.week == monday { return true }
            if let d = todo.day { return range.contains(d) }
            return false
        })
    }

    /// Todos whose `projectID == id`.
    public static func project(_ todos: some Sequence<TodoSpec>, id: UUID) -> RingProgress {
        progress(of: todos.filter { $0.projectID == id })
    }

    /// Plain done/total over any todos.
    public static func progress(of todos: some Sequence<TodoSpec>) -> RingProgress {
        var done = 0
        var total = 0
        for todo in todos {
            total += 1
            if todo.isDone { done += 1 }
        }
        return RingProgress(done: done, total: total)
    }

    /// Sort order for a list: open before done, then priority ascending (1 first).
    public static func listOrder(_ a: TodoSpec, _ b: TodoSpec) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        return a.priority < b.priority
    }
}
