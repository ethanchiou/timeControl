import Foundation
import SwiftData
import TimeControlCore

extension SchemaV1 {
    /// A task. Scope: `dayKey` set → that day's list; else `weekKey` set → that week's list; else project backlog.
    @Model
    final class TodoItem {
        var uuid: UUID = UUID()
        var title: String = ""
        var notes: String = ""
        /// 1 urgent … 4 low.
        var priority: Int = 3
        var isDone: Bool = false
        var completedAt: Date?
        var dayKey: Int?
        /// Monday of the week bucket.
        var weekKey: Int?
        var dueDayKey: Int?
        var sortOrder: Int = 0
        var createdAt: Date = Date()

        var project: Project?

        init(title: String, priority: Int = 3, day: DayKey? = nil, week: DayKey? = nil, dueDay: DayKey? = nil, project: Project? = nil, notes: String = "", sortOrder: Int = 0) {
            self.title = title
            self.priority = min(4, max(1, priority))
            self.dayKey = day?.rawValue
            self.weekKey = week?.weekStart.rawValue
            self.dueDayKey = dueDay?.rawValue
            self.project = project
            self.notes = notes
            self.sortOrder = sortOrder
        }
    }
}

extension TodoItem {
    var day: DayKey? {
        get { dayKey.map(DayKey.init(rawValue:)) }
        set { dayKey = newValue?.rawValue }
    }

    var week: DayKey? {
        get { weekKey.map(DayKey.init(rawValue:)) }
        set { weekKey = newValue?.weekStart.rawValue }
    }

    var dueDay: DayKey? {
        get { dueDayKey.map(DayKey.init(rawValue:)) }
        set { dueDayKey = newValue?.rawValue }
    }

    var spec: TodoSpec {
        TodoSpec(id: uuid, isDone: isDone, priority: priority, day: day, week: week, projectID: project?.uuid)
    }

    func setDone(_ done: Bool) {
        isDone = done
        completedAt = done ? Date() : nil
    }

    /// Move to a specific day (clears the week bucket).
    func schedule(on day: DayKey) {
        self.day = day
        self.week = nil
    }

    /// Move to a week bucket (clears the day).
    func schedule(inWeekOf day: DayKey) {
        self.day = nil
        self.week = day.weekStart
    }

    func unschedule() {
        day = nil
        week = nil
    }

    /// Open before done, then priority, then sortOrder, then creation.
    static func listOrder(_ a: TodoItem, _ b: TodoItem) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        if a.priority != b.priority { return a.priority < b.priority }
        if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
        return a.createdAt < b.createdAt
    }
}
