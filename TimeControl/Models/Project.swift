import Foundation
import SwiftData
import TimeControlCore

enum ProjectStatus: String, CaseIterable, Codable, Sendable, Identifiable {
    case active, paused, done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: "Active"
        case .paused: "Paused"
        case .done: "Done"
        }
    }
}

extension SchemaV1 {
    /// A higher-level goal that groups todos. Progress = done/total of its todos.
    @Model
    final class Project {
        var uuid: UUID = UUID()
        var title: String = ""
        var summary: String = ""
        var notes: String = ""
        var statusRaw: String = ProjectStatus.active.rawValue
        /// 1 urgent … 4 low.
        var priority: Int = 3
        var targetDayKey: Int?
        var colorHex: String = "#4F7CFF"
        var sortOrder: Int = 0
        var createdAt: Date = Date()
        var completedAt: Date?

        @Relationship(deleteRule: .nullify, inverse: \TodoItem.project)
        var todos: [TodoItem]?

        init(title: String, summary: String = "", priority: Int = 3, targetDay: DayKey? = nil, colorHex: String = "#4F7CFF", sortOrder: Int = 0) {
            self.title = title
            self.summary = summary
            self.priority = min(4, max(1, priority))
            self.targetDayKey = targetDay?.rawValue
            self.colorHex = colorHex
            self.sortOrder = sortOrder
        }
    }
}

extension Project {
    var status: ProjectStatus {
        get { ProjectStatus(rawValue: statusRaw) ?? .active }
        set {
            statusRaw = newValue.rawValue
            completedAt = newValue == .done ? (completedAt ?? Date()) : nil
        }
    }

    var targetDay: DayKey? {
        get { targetDayKey.map(DayKey.init(rawValue:)) }
        set { targetDayKey = newValue?.rawValue }
    }

    var todoSpecs: [TodoSpec] { (todos ?? []).map(\.spec) }

    var progress: RingProgress { RingMath.progress(of: todoSpecs) }

    var openTodos: [TodoItem] {
        (todos ?? []).filter { !$0.isDone }.sorted(by: TodoItem.listOrder)
    }

    var doneTodos: [TodoItem] {
        (todos ?? []).filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
}
