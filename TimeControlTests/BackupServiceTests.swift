import Foundation
import SwiftData
import Testing
import TimeControlCore
@testable import TimeControl

@MainActor
@Suite struct BackupServiceTests {
    /// Holds the container: a `ModelContext` whose container has been deallocated traps silently on the next insert.
    struct Store {
        let container: ModelContainer
        var ctx: ModelContext { container.mainContext }
    }

    func makeStore() throws -> Store {
        Store(container: try ModelContainerFactory.make(inMemory: true))
    }

    /// `SampleData` plus one occurrence exception (it seeds none) so every entity kind exercises its relationship.
    func loadFixture(into ctx: ModelContext) throws {
        SampleData.load(into: ctx)
        let series = try #require(try ctx.fetch(FetchDescriptor<Series>()).first)
        ctx.insert(OccurrenceException(series: series, day: DayKey.today()))
        try ctx.save()
    }

    func todoItem(uuid: UUID, in ctx: ModelContext) throws -> TodoItem? {
        var d = FetchDescriptor<TodoItem>(predicate: #Predicate { $0.uuid == uuid })
        d.fetchLimit = 1
        return try ctx.fetch(d).first
    }

    func exception(uuid: UUID, in ctx: ModelContext) throws -> OccurrenceException? {
        var d = FetchDescriptor<OccurrenceException>(predicate: #Predicate { $0.uuid == uuid })
        d.fetchLimit = 1
        return try ctx.fetch(d).first
    }

    @Test func exportCountsMatchTheFixture() throws {
        let store = try makeStore()
        try loadFixture(into: store.ctx)

        let doc = try BackupService.export(from: store.ctx)

        #expect(doc.terms.count == 1)
        #expect(doc.series.count == 5)
        #expect(doc.blackouts.count == 1)
        #expect(doc.exceptions.count == 1)
        #expect(doc.events.count == 4)
        #expect(doc.projects.count == 3)
        #expect(doc.todos.count == 11)
    }

    @Test func roundTripThroughJSONAndReplaceImportPreservesCountsAndRelationships() throws {
        let source = try makeStore()
        try loadFixture(into: source.ctx)
        let sourceDoc = try BackupService.export(from: source.ctx)
        let data = try sourceDoc.encode()

        let destination = try makeStore()
        let decoded = try BackupDocument.decode(data)
        let summary = try BackupService.importDocument(decoded, into: destination.ctx, mode: .replace)

        #expect(summary.inserted == sourceDoc.entityCount)
        #expect(summary.updated == 0)
        #expect(summary.skipped == 0)

        let destDoc = try BackupService.export(from: destination.ctx)
        #expect(destDoc.terms.count == sourceDoc.terms.count)
        #expect(destDoc.series.count == sourceDoc.series.count)
        #expect(destDoc.blackouts.count == sourceDoc.blackouts.count)
        #expect(destDoc.exceptions.count == sourceDoc.exceptions.count)
        #expect(destDoc.events.count == sourceDoc.events.count)
        #expect(destDoc.projects.count == sourceDoc.projects.count)
        #expect(destDoc.todos.count == sourceDoc.todos.count)

        // Relationships resolved by uuid: series -> term, todo -> project, blackout -> term, exception -> series.
        let seriesDTO = try #require(sourceDoc.series.first { $0.termID != nil })
        let importedSeries = try #require(destination.ctx.series(uuid: seriesDTO.id))
        #expect(importedSeries.term?.uuid == seriesDTO.termID)

        let todoDTO = try #require(sourceDoc.todos.first { $0.projectID != nil })
        let fetchedTodo = try todoItem(uuid: todoDTO.id, in: destination.ctx)
        let importedTodo = try #require(fetchedTodo)
        #expect(importedTodo.project?.uuid == todoDTO.projectID)

        let blackoutDTO = try #require(sourceDoc.blackouts.first { $0.termID != nil })
        let importedBlackout = try #require(destination.ctx.blackout(uuid: blackoutDTO.id))
        #expect(importedBlackout.term?.uuid == blackoutDTO.termID)

        let exceptionDTO = try #require(sourceDoc.exceptions.first)
        let fetchedException = try exception(uuid: exceptionDTO.id, in: destination.ctx)
        let importedException = try #require(fetchedException)
        #expect(importedException.series?.uuid == exceptionDTO.seriesID)
    }

    @Test func jsonRoundTripPreservesScalarFields() throws {
        let store = try makeStore()
        try loadFixture(into: store.ctx)
        let doc = try BackupService.export(from: store.ctx)
        let data = try doc.encode()
        let decoded = try BackupDocument.decode(data)

        let originalSeries = try #require(doc.series.first)
        let decodedSeries = try #require(decoded.series.first { $0.id == originalSeries.id })
        #expect(decodedSeries.weekdaysMask == originalSeries.weekdaysMask)
        #expect(decodedSeries.startMinute == originalSeries.startMinute)
        #expect(decodedSeries.endWeek == originalSeries.endWeek)

        let originalTodo = try #require(doc.todos.first { $0.dayKey != nil })
        let decodedTodo = try #require(decoded.todos.first { $0.id == originalTodo.id })
        #expect(decodedTodo.dayKey == originalTodo.dayKey)
        #expect(decodedTodo.priority == originalTodo.priority)
        #expect(decodedTodo.isDone == originalTodo.isDone)
    }

    @Test func mergeIntoExistingFixtureUpdatesInPlaceRatherThanDuplicating() throws {
        let store = try makeStore()
        try loadFixture(into: store.ctx)
        let doc = try BackupService.export(from: store.ctx)

        var modified = doc
        modified.terms[0].name = "Renamed Term"

        let summary = try BackupService.importDocument(modified, into: store.ctx, mode: .merge)

        #expect(summary.inserted == 0)
        #expect(summary.updated == doc.entityCount)
        #expect(summary.skipped == 0)

        let afterDoc = try BackupService.export(from: store.ctx)
        #expect(afterDoc.entityCount == doc.entityCount)
        #expect(afterDoc.terms.first?.name == "Renamed Term")
    }

    @Test func mergeInsertsNewTodoLinkedToExistingProject() throws {
        let store = try makeStore()
        try loadFixture(into: store.ctx)
        let doc = try BackupService.export(from: store.ctx)
        let projectID = try #require(doc.projects.first?.id)

        var addition = doc
        let newTodoID = UUID()
        addition.todos.append(TodoDTO(id: newTodoID, title: "New task", projectID: projectID))

        let summary = try BackupService.importDocument(addition, into: store.ctx, mode: .merge)

        #expect(summary.inserted == 1)
        #expect(summary.updated == doc.entityCount)

        let fetchedInserted = try todoItem(uuid: newTodoID, in: store.ctx)
        let inserted = try #require(fetchedInserted)
        #expect(inserted.title == "New task")
        #expect(inserted.project?.uuid == projectID)
    }

    @Test func danglingProjectReferenceLeavesProjectNilWithoutThrowing() throws {
        let store = try makeStore()
        let danglingProjectID = UUID()
        let doc = BackupDocument(todos: [TodoDTO(title: "Orphan", projectID: danglingProjectID)])

        let summary = try BackupService.importDocument(doc, into: store.ctx, mode: .replace)
        #expect(summary.inserted == 1)

        let todos = try store.ctx.fetch(FetchDescriptor<TodoItem>())
        #expect(todos.count == 1)
        #expect(todos.first?.project == nil)
    }

    @Test func groupEventFieldsRoundTripThroughExportAndImport() throws {
        let store = try makeStore()
        let groupID = UUID()
        let authorID = UUID()
        let event = Event(title: "Study session", kind: .other, start: .now, end: .now.addingTimeInterval(3600), groupID: groupID)
        event.authorID = authorID
        store.ctx.insert(event)
        try store.ctx.save()

        let doc = try BackupService.export(from: store.ctx)
        let exported = try #require(doc.events.first { $0.id == event.uuid })
        #expect(exported.groupID == groupID)
        #expect(exported.authorID == authorID)

        let data = try doc.encode()
        let decoded = try BackupDocument.decode(data)

        let destination = try makeStore()
        _ = try BackupService.importDocument(decoded, into: destination.ctx, mode: .replace)
        let imported = try #require(destination.ctx.event(uuid: event.uuid))
        #expect(imported.groupID == groupID)
        #expect(imported.authorID == authorID)
    }

    @Test func suggestedFilenameFormat() {
        let date = DayKey(year: 2026, month: 9, day: 3).startDate()
        #expect(BackupService.suggestedFilename(now: date) == "TimeControl-2026-09-03.json")
    }
}
