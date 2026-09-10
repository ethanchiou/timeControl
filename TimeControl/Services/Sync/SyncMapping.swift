import Foundation
import SwiftData
import TimeControlCore

// Model ↔ row conversions for every synced table, plus the lookups the pull side needs to wire
// relationships back up. Rows come in parents-first (see `SyncTable.pushOrder`), so a child's parent
// is already in the store by the time the child is applied; a missing parent just leaves the
// relationship nil, exactly as the backup import does.

extension ModelContext {
    func term(uuid: UUID) -> Term? {
        var d = FetchDescriptor<Term>(predicate: #Predicate { $0.uuid == uuid })
        d.fetchLimit = 1
        return try? fetch(d).first
    }

    func exception(uuid: UUID) -> OccurrenceException? {
        var d = FetchDescriptor<OccurrenceException>(predicate: #Predicate { $0.uuid == uuid })
        d.fetchLimit = 1
        return try? fetch(d).first
    }

    func todo(uuid: UUID) -> TodoItem? {
        var d = FetchDescriptor<TodoItem>(predicate: #Predicate { $0.uuid == uuid })
        d.fetchLimit = 1
        return try? fetch(d).first
    }
}

// MARK: Term

extension Term {
    func row(userID: UUID) -> TermRow {
        TermRow(id: uuid, userId: userID, name: name, startDayKey: startDayKey, endDayKey: endDayKey, isArchived: isArchived, createdAt: createdAt, updatedAt: nil, deletedAt: nil)
    }

    func apply(_ row: TermRow) {
        name = row.name
        startDayKey = row.startDayKey
        endDayKey = row.endDayKey
        isArchived = row.isArchived
        if let created = row.createdAt { createdAt = created }
        syncedAt = row.updatedAt
    }

    static func make(from row: TermRow) -> Term {
        let term = Term(name: row.name, start: DayKey(rawValue: row.startDayKey), end: DayKey(rawValue: row.endDayKey))
        term.uuid = row.id
        term.apply(row)
        return term
    }
}

// MARK: Series

extension Series {
    func row(userID: UUID) -> SeriesRow {
        SeriesRow(
            id: uuid, userId: userID, termId: term?.uuid, title: title, kind: kindRaw,
            weekdaysMask: weekdaysMask, startMinute: startMinute, endMinute: endMinute,
            intervalWeeks: intervalWeeks, startWeek: startWeek, endWeek: endWeek,
            location: location, notes: notes, colorHex: colorHex, createdAt: createdAt, updatedAt: nil, deletedAt: nil
        )
    }

    @MainActor func apply(_ row: SeriesRow, in context: ModelContext) {
        title = row.title
        kindRaw = row.kind
        weekdaysMask = row.weekdaysMask
        startMinute = row.startMinute
        endMinute = row.endMinute
        intervalWeeks = row.intervalWeeks
        startWeek = row.startWeek
        endWeek = row.endWeek
        location = row.location
        notes = row.notes
        colorHex = row.colorHex
        term = row.termId.flatMap { context.term(uuid: $0) }
        if let created = row.createdAt { createdAt = created }
        syncedAt = row.updatedAt
    }

    @MainActor static func make(from row: SeriesRow, in context: ModelContext) -> Series {
        let series = Series(
            title: row.title, kind: Kind(rawValue: row.kind) ?? .course, weekdays: Weekday.set(fromMask: row.weekdaysMask),
            startMinute: row.startMinute, endMinute: row.endMinute, intervalWeeks: row.intervalWeeks,
            startWeek: row.startWeek, endWeek: row.endWeek, location: row.location, notes: row.notes
        )
        series.uuid = row.id
        context.insert(series)
        series.apply(row, in: context)
        return series
    }
}

// MARK: Blackout

extension Blackout {
    func row(userID: UUID) -> BlackoutRow {
        BlackoutRow(id: uuid, userId: userID, termId: term?.uuid, startDayKey: startDayKey, endDayKey: endDayKey, kinds: kindsRaw, reason: reason, createdAt: createdAt, updatedAt: nil, deletedAt: nil)
    }

    @MainActor func apply(_ row: BlackoutRow, in context: ModelContext) {
        startDayKey = row.startDayKey
        endDayKey = row.endDayKey
        kindsRaw = row.kinds
        reason = row.reason
        term = row.termId.flatMap { context.term(uuid: $0) }
        if let created = row.createdAt { createdAt = created }
        syncedAt = row.updatedAt
    }

    @MainActor static func make(from row: BlackoutRow, in context: ModelContext) -> Blackout {
        let blackout = Blackout(start: DayKey(rawValue: row.startDayKey), end: DayKey(rawValue: row.endDayKey), reason: row.reason)
        blackout.uuid = row.id
        context.insert(blackout)
        blackout.apply(row, in: context)
        return blackout
    }
}

// MARK: OccurrenceException

extension OccurrenceException {
    func row(userID: UUID) -> ExceptionRow {
        ExceptionRow(id: uuid, userId: userID, seriesId: series?.uuid, dayKey: dayKey, kind: kindRaw, createdAt: createdAt, updatedAt: nil, deletedAt: nil)
    }

    @MainActor func apply(_ row: ExceptionRow, in context: ModelContext) {
        dayKey = row.dayKey
        kindRaw = row.kind
        series = row.seriesId.flatMap { context.series(uuid: $0) }
        if let created = row.createdAt { createdAt = created }
        syncedAt = row.updatedAt
    }

    /// Nil when the series is not in the store: an exception without a series is meaningless.
    @MainActor static func make(from row: ExceptionRow, in context: ModelContext) -> OccurrenceException? {
        guard let seriesID = row.seriesId, let series = context.series(uuid: seriesID) else { return nil }
        let exception = OccurrenceException(series: series, day: DayKey(rawValue: row.dayKey), kind: ExceptionKind(rawValue: row.kind) ?? .skipped)
        exception.uuid = row.id
        context.insert(exception)
        exception.apply(row, in: context)
        return exception
    }
}

// MARK: Event

extension Event {
    /// `userID` is the signed-in user; a group event keeps its original author.
    func row(userID: UUID) -> EventRow {
        EventRow(
            id: uuid, userId: authorID ?? userID, groupId: groupID, title: title, kind: kindRaw,
            startAt: startDate, endAt: endDate, isAllDay: isAllDay, location: location, notes: notes,
            reminderOffsetsMinutes: reminderOffsetsMinutes, isRoutine: isRoutine, colorHex: colorHex,
            createdAt: createdAt, updatedAt: nil, deletedAt: nil
        )
    }

    func apply(_ row: EventRow) {
        title = row.title
        kindRaw = row.kind
        startDate = row.startAt
        endDate = row.endAt
        isAllDay = row.isAllDay
        location = row.location
        notes = row.notes
        reminderOffsetsMinutes = row.reminderOffsetsMinutes
        isRoutine = row.isRoutine
        colorHex = row.colorHex
        groupID = row.groupId
        authorID = row.userId
        if let created = row.createdAt { createdAt = created }
        syncedAt = row.updatedAt
    }

    static func make(from row: EventRow) -> Event {
        let event = Event(title: row.title, kind: Kind(rawValue: row.kind) ?? .other, start: row.startAt, end: row.endAt, isAllDay: row.isAllDay, location: row.location, notes: row.notes, reminderOffsetsMinutes: row.reminderOffsetsMinutes, isRoutine: row.isRoutine, groupID: row.groupId)
        event.uuid = row.id
        event.apply(row)
        return event
    }
}

// MARK: Project

extension Project {
    func row(userID: UUID) -> ProjectRow {
        ProjectRow(
            id: uuid, userId: userID, title: title, summary: summary, notes: notes, status: statusRaw,
            priority: priority, targetDayKey: targetDayKey, colorHex: colorHex, sortOrder: sortOrder,
            completedAt: completedAt, createdAt: createdAt, updatedAt: nil, deletedAt: nil
        )
    }

    func apply(_ row: ProjectRow) {
        title = row.title
        summary = row.summary
        notes = row.notes
        statusRaw = row.status
        priority = row.priority
        targetDayKey = row.targetDayKey
        colorHex = row.colorHex
        sortOrder = row.sortOrder
        completedAt = row.completedAt
        if let created = row.createdAt { createdAt = created }
        syncedAt = row.updatedAt
    }

    static func make(from row: ProjectRow) -> Project {
        let project = Project(title: row.title, summary: row.summary, priority: row.priority, colorHex: row.colorHex, sortOrder: row.sortOrder)
        project.uuid = row.id
        project.apply(row)
        return project
    }
}

// MARK: TodoItem

extension TodoItem {
    func row(userID: UUID) -> TodoItemRow {
        TodoItemRow(
            id: uuid, userId: userID, projectId: project?.uuid, title: title, notes: notes, priority: priority,
            isDone: isDone, completedAt: completedAt, dayKey: dayKey, weekKey: weekKey, dueDayKey: dueDayKey,
            sortOrder: sortOrder, createdAt: createdAt, updatedAt: nil, deletedAt: nil
        )
    }

    @MainActor func apply(_ row: TodoItemRow, in context: ModelContext) {
        title = row.title
        notes = row.notes
        priority = row.priority
        isDone = row.isDone
        completedAt = row.completedAt
        dayKey = row.dayKey
        weekKey = row.weekKey
        dueDayKey = row.dueDayKey
        sortOrder = row.sortOrder
        project = row.projectId.flatMap { context.project(uuid: $0) }
        if let created = row.createdAt { createdAt = created }
        syncedAt = row.updatedAt
    }

    @MainActor static func make(from row: TodoItemRow, in context: ModelContext) -> TodoItem {
        let todo = TodoItem(title: row.title, priority: row.priority, notes: row.notes, sortOrder: row.sortOrder)
        todo.uuid = row.id
        context.insert(todo)
        todo.apply(row, in: context)
        return todo
    }
}
