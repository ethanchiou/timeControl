import Foundation
import SwiftData
import TimeControlCore

enum BackupImportMode {
    case replace
    case merge
}

struct BackupImportSummary: Equatable {
    var inserted: Int
    var updated: Int
    var skipped: Int
}

/// Exports every record to a ``BackupDocument`` (JSON) and imports one back, either replacing
/// all local data or merging by `uuid`.
@MainActor
enum BackupService {
    // MARK: - Export

    static func export(from context: ModelContext) throws -> BackupDocument {
        let terms = try context.fetch(FetchDescriptor<Term>()).map { term in
            TermDTO(id: term.uuid, name: term.name, startDayKey: term.startDayKey, endDayKey: term.endDayKey, isArchived: term.isArchived)
        }
        let series = try context.fetch(FetchDescriptor<Series>()).map { series in
            SeriesDTO(
                id: series.uuid,
                termID: series.term?.uuid,
                title: series.title,
                kindRaw: series.kindRaw,
                weekdaysMask: series.weekdaysMask,
                startMinute: series.startMinute,
                endMinute: series.endMinute,
                intervalWeeks: series.intervalWeeks,
                startWeek: series.startWeek,
                endWeek: series.endWeek,
                location: series.location,
                notes: series.notes,
                colorHex: series.colorHex
            )
        }
        let blackouts = try context.fetch(FetchDescriptor<Blackout>()).map { blackout in
            BlackoutDTO(
                id: blackout.uuid,
                termID: blackout.term?.uuid,
                startDayKey: blackout.startDayKey,
                endDayKey: blackout.endDayKey,
                kindsRaw: blackout.kindsRaw,
                reason: blackout.reason
            )
        }
        let exceptions = try context.fetch(FetchDescriptor<OccurrenceException>()).map { exception in
            ExceptionDTO(id: exception.uuid, seriesID: exception.series?.uuid, dayKey: exception.dayKey, kindRaw: exception.kindRaw)
        }
        let events = try context.fetch(FetchDescriptor<Event>()).map { event in
            EventDTO(
                id: event.uuid,
                title: event.title,
                kindRaw: event.kindRaw,
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                location: event.location,
                notes: event.notes,
                reminderOffsetsMinutes: event.reminderOffsetsMinutes
            )
        }
        let projects = try context.fetch(FetchDescriptor<Project>()).map { project in
            ProjectDTO(
                id: project.uuid,
                title: project.title,
                summary: project.summary,
                notes: project.notes,
                statusRaw: project.statusRaw,
                priority: project.priority,
                targetDayKey: project.targetDayKey,
                colorHex: project.colorHex,
                sortOrder: project.sortOrder,
                createdAt: project.createdAt,
                completedAt: project.completedAt
            )
        }
        let todos = try context.fetch(FetchDescriptor<TodoItem>()).map { todo in
            TodoDTO(
                id: todo.uuid,
                title: todo.title,
                notes: todo.notes,
                priority: todo.priority,
                isDone: todo.isDone,
                completedAt: todo.completedAt,
                dayKey: todo.dayKey,
                weekKey: todo.weekKey,
                dueDayKey: todo.dueDayKey,
                sortOrder: todo.sortOrder,
                createdAt: todo.createdAt,
                projectID: todo.project?.uuid
            )
        }
        return BackupDocument(terms: terms, series: series, blackouts: blackouts, exceptions: exceptions, events: events, projects: projects, todos: todos)
    }

    static func exportData(from context: ModelContext) throws -> Data {
        try export(from: context).encode()
    }

    // MARK: - Import

    @discardableResult
    static func importDocument(_ doc: BackupDocument, into context: ModelContext, mode: BackupImportMode) throws -> BackupImportSummary {
        switch mode {
        case .replace:
            try SampleData.wipe(context)
            return try insertAll(doc, into: context)
        case .merge:
            return try mergeAll(doc, into: context)
        }
    }

    static func importData(_ data: Data, into context: ModelContext, mode: BackupImportMode) throws -> BackupImportSummary {
        let doc = try BackupDocument.decode(data)
        return try importDocument(doc, into: context, mode: mode)
    }

    // MARK: - Replace

    private static func insertAll(_ doc: BackupDocument, into context: ModelContext) throws -> BackupImportSummary {
        var termsByID: [UUID: Term] = [:]
        for dto in doc.terms {
            let term = Term(name: dto.name, start: DayKey(rawValue: dto.startDayKey), end: DayKey(rawValue: dto.endDayKey))
            term.uuid = dto.id
            term.isArchived = dto.isArchived
            context.insert(term)
            termsByID[dto.id] = term
        }

        var seriesByID: [UUID: Series] = [:]
        for dto in doc.series {
            let series = Series(
                title: dto.title,
                weekdays: Weekday.set(fromMask: dto.weekdaysMask),
                startMinute: dto.startMinute,
                endMinute: dto.endMinute,
                intervalWeeks: dto.intervalWeeks,
                startWeek: dto.startWeek,
                endWeek: dto.endWeek,
                location: dto.location,
                notes: dto.notes
            )
            series.uuid = dto.id
            series.kindRaw = dto.kindRaw
            series.colorHex = dto.colorHex
            series.term = dto.termID.flatMap { termsByID[$0] }
            context.insert(series)
            seriesByID[dto.id] = series
        }

        for dto in doc.blackouts {
            let blackout = Blackout(start: DayKey(rawValue: dto.startDayKey), end: DayKey(rawValue: dto.endDayKey), reason: dto.reason)
            blackout.uuid = dto.id
            blackout.kindsRaw = dto.kindsRaw
            blackout.term = dto.termID.flatMap { termsByID[$0] }
            context.insert(blackout)
        }

        for dto in doc.exceptions {
            guard let series = dto.seriesID.flatMap({ seriesByID[$0] }) else { continue }
            let exception = OccurrenceException(series: series, day: DayKey(rawValue: dto.dayKey))
            exception.uuid = dto.id
            exception.kindRaw = dto.kindRaw
            context.insert(exception)
        }

        for dto in doc.events {
            let event = Event(
                title: dto.title,
                kind: Kind(rawValue: dto.kindRaw) ?? .other,
                start: dto.startDate,
                end: dto.endDate,
                isAllDay: dto.isAllDay,
                location: dto.location,
                notes: dto.notes,
                reminderOffsetsMinutes: dto.reminderOffsetsMinutes
            )
            event.uuid = dto.id
            context.insert(event)
        }

        var projectsByID: [UUID: Project] = [:]
        for dto in doc.projects {
            let project = Project(title: dto.title, summary: dto.summary, priority: dto.priority, colorHex: dto.colorHex, sortOrder: dto.sortOrder)
            project.uuid = dto.id
            project.notes = dto.notes
            project.statusRaw = dto.statusRaw
            project.targetDayKey = dto.targetDayKey
            project.createdAt = dto.createdAt
            project.completedAt = dto.completedAt
            context.insert(project)
            projectsByID[dto.id] = project
        }

        for dto in doc.todos {
            let todo = TodoItem(title: dto.title, priority: dto.priority, notes: dto.notes, sortOrder: dto.sortOrder)
            todo.uuid = dto.id
            todo.isDone = dto.isDone
            todo.completedAt = dto.completedAt
            todo.dayKey = dto.dayKey
            todo.weekKey = dto.weekKey
            todo.dueDayKey = dto.dueDayKey
            todo.createdAt = dto.createdAt
            todo.project = dto.projectID.flatMap { projectsByID[$0] }
            context.insert(todo)
        }

        try context.save()
        return BackupImportSummary(inserted: doc.entityCount, updated: 0, skipped: 0)
    }

    // MARK: - Merge

    private static func mergeAll(_ doc: BackupDocument, into context: ModelContext) throws -> BackupImportSummary {
        var inserted = 0
        var updated = 0

        var termsByID: [UUID: Term] = [:]
        for existing in try context.fetch(FetchDescriptor<Term>()) { termsByID[existing.uuid] = existing }
        for dto in doc.terms {
            if let term = termsByID[dto.id] {
                term.name = dto.name
                term.startDayKey = dto.startDayKey
                term.endDayKey = dto.endDayKey
                term.isArchived = dto.isArchived
                updated += 1
            } else {
                let term = Term(name: dto.name, start: DayKey(rawValue: dto.startDayKey), end: DayKey(rawValue: dto.endDayKey))
                term.uuid = dto.id
                term.isArchived = dto.isArchived
                context.insert(term)
                termsByID[dto.id] = term
                inserted += 1
            }
        }

        var seriesByID: [UUID: Series] = [:]
        for existing in try context.fetch(FetchDescriptor<Series>()) { seriesByID[existing.uuid] = existing }
        for dto in doc.series {
            let term = dto.termID.flatMap { termsByID[$0] }
            if let series = seriesByID[dto.id] {
                series.title = dto.title
                series.kindRaw = dto.kindRaw
                series.weekdaysMask = dto.weekdaysMask
                series.startMinute = dto.startMinute
                series.endMinute = dto.endMinute
                series.intervalWeeks = dto.intervalWeeks
                series.startWeek = dto.startWeek
                series.endWeek = dto.endWeek
                series.location = dto.location
                series.notes = dto.notes
                series.colorHex = dto.colorHex
                series.term = term
                updated += 1
            } else {
                let series = Series(
                    title: dto.title,
                    weekdays: Weekday.set(fromMask: dto.weekdaysMask),
                    startMinute: dto.startMinute,
                    endMinute: dto.endMinute,
                    intervalWeeks: dto.intervalWeeks,
                    startWeek: dto.startWeek,
                    endWeek: dto.endWeek,
                    location: dto.location,
                    notes: dto.notes
                )
                series.uuid = dto.id
                series.kindRaw = dto.kindRaw
                series.colorHex = dto.colorHex
                series.term = term
                context.insert(series)
                seriesByID[dto.id] = series
                inserted += 1
            }
        }

        var blackoutsByID: [UUID: Blackout] = [:]
        for existing in try context.fetch(FetchDescriptor<Blackout>()) { blackoutsByID[existing.uuid] = existing }
        for dto in doc.blackouts {
            let term = dto.termID.flatMap { termsByID[$0] }
            if let blackout = blackoutsByID[dto.id] {
                blackout.startDayKey = dto.startDayKey
                blackout.endDayKey = dto.endDayKey
                blackout.kindsRaw = dto.kindsRaw
                blackout.reason = dto.reason
                blackout.term = term
                updated += 1
            } else {
                let blackout = Blackout(start: DayKey(rawValue: dto.startDayKey), end: DayKey(rawValue: dto.endDayKey), reason: dto.reason)
                blackout.uuid = dto.id
                blackout.kindsRaw = dto.kindsRaw
                blackout.term = term
                context.insert(blackout)
                inserted += 1
            }
        }

        var exceptionsByID: [UUID: OccurrenceException] = [:]
        for existing in try context.fetch(FetchDescriptor<OccurrenceException>()) { exceptionsByID[existing.uuid] = existing }
        for dto in doc.exceptions {
            let series = dto.seriesID.flatMap { seriesByID[$0] }
            if let exception = exceptionsByID[dto.id] {
                exception.dayKey = dto.dayKey
                exception.kindRaw = dto.kindRaw
                exception.series = series
                updated += 1
            } else {
                guard let series else { continue }
                let exception = OccurrenceException(series: series, day: DayKey(rawValue: dto.dayKey))
                exception.uuid = dto.id
                exception.kindRaw = dto.kindRaw
                context.insert(exception)
                inserted += 1
            }
        }

        var eventsByID: [UUID: Event] = [:]
        for existing in try context.fetch(FetchDescriptor<Event>()) { eventsByID[existing.uuid] = existing }
        for dto in doc.events {
            if let event = eventsByID[dto.id] {
                event.title = dto.title
                event.kindRaw = dto.kindRaw
                event.startDate = dto.startDate
                event.endDate = dto.endDate
                event.isAllDay = dto.isAllDay
                event.location = dto.location
                event.notes = dto.notes
                event.reminderOffsetsMinutes = dto.reminderOffsetsMinutes
                updated += 1
            } else {
                let event = Event(
                    title: dto.title,
                    kind: Kind(rawValue: dto.kindRaw) ?? .other,
                    start: dto.startDate,
                    end: dto.endDate,
                    isAllDay: dto.isAllDay,
                    location: dto.location,
                    notes: dto.notes,
                    reminderOffsetsMinutes: dto.reminderOffsetsMinutes
                )
                event.uuid = dto.id
                context.insert(event)
                inserted += 1
            }
        }

        var projectsByID: [UUID: Project] = [:]
        for existing in try context.fetch(FetchDescriptor<Project>()) { projectsByID[existing.uuid] = existing }
        for dto in doc.projects {
            if let project = projectsByID[dto.id] {
                project.title = dto.title
                project.summary = dto.summary
                project.notes = dto.notes
                project.statusRaw = dto.statusRaw
                project.priority = dto.priority
                project.targetDayKey = dto.targetDayKey
                project.colorHex = dto.colorHex
                project.sortOrder = dto.sortOrder
                project.completedAt = dto.completedAt
                updated += 1
            } else {
                let project = Project(title: dto.title, summary: dto.summary, priority: dto.priority, colorHex: dto.colorHex, sortOrder: dto.sortOrder)
                project.uuid = dto.id
                project.notes = dto.notes
                project.statusRaw = dto.statusRaw
                project.targetDayKey = dto.targetDayKey
                project.createdAt = dto.createdAt
                project.completedAt = dto.completedAt
                context.insert(project)
                projectsByID[dto.id] = project
                inserted += 1
            }
        }

        var todosByID: [UUID: TodoItem] = [:]
        for existing in try context.fetch(FetchDescriptor<TodoItem>()) { todosByID[existing.uuid] = existing }
        for dto in doc.todos {
            let project = dto.projectID.flatMap { projectsByID[$0] }
            if let todo = todosByID[dto.id] {
                todo.title = dto.title
                todo.notes = dto.notes
                todo.priority = dto.priority
                todo.isDone = dto.isDone
                todo.completedAt = dto.completedAt
                todo.dayKey = dto.dayKey
                todo.weekKey = dto.weekKey
                todo.dueDayKey = dto.dueDayKey
                todo.sortOrder = dto.sortOrder
                todo.project = project
                updated += 1
            } else {
                let todo = TodoItem(title: dto.title, priority: dto.priority, notes: dto.notes, sortOrder: dto.sortOrder)
                todo.uuid = dto.id
                todo.isDone = dto.isDone
                todo.completedAt = dto.completedAt
                todo.dayKey = dto.dayKey
                todo.weekKey = dto.weekKey
                todo.dueDayKey = dto.dueDayKey
                todo.createdAt = dto.createdAt
                todo.project = project
                context.insert(todo)
                inserted += 1
            }
        }

        try context.save()
        return BackupImportSummary(inserted: inserted, updated: updated, skipped: 0)
    }

    // MARK: - Filename

    static func suggestedFilename(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return "TimeControl-\(formatter.string(from: now)).json"
    }
}
