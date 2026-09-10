import Foundation
import Testing
@testable import TimeControlCore

@Suite struct BackupTests {
    // Fixed UUIDs and whole-second dates so encode -> decode round trips exactly.
    let termID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let seriesID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let blackoutID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    let exceptionID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    let eventID = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
    let projectID = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
    let todoID = UUID(uuidString: "00000000-0000-0000-0000-000000000007")!
    let groupID = UUID(uuidString: "00000000-0000-0000-0000-000000000008")!
    let authorID = UUID(uuidString: "00000000-0000-0000-0000-000000000009")!

    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    func fullDocument() -> BackupDocument {
        BackupDocument(
            exportedAt: fixedDate,
            terms: [TermDTO(id: termID, name: "Fall 2026", startDayKey: 100, endDayKey: 200, isArchived: false)],
            series: [SeriesDTO(id: seriesID, termID: termID, title: "CS201", kindRaw: "course", weekdaysMask: 0b0010101, startMinute: 600, endMinute: 690, intervalWeeks: 1, startWeek: 1, endWeek: 14, location: "Room 5", notes: "Bring laptop", colorHex: "#4F7CFF")],
            blackouts: [BlackoutDTO(id: blackoutID, termID: termID, startDayKey: 150, endDayKey: 156, kindsRaw: ["course"], reason: "Midterms")],
            exceptions: [ExceptionDTO(id: exceptionID, seriesID: seriesID, dayKey: 120, kindRaw: "skipped")],
            events: [EventDTO(id: eventID, title: "Interview", kindRaw: "interview", startDate: fixedDate, endDate: fixedDate.addingTimeInterval(3600), isAllDay: false, location: "Zoom", notes: "Bring resume", reminderOffsetsMinutes: [30, 60], colorHex: "#EC4899", groupID: groupID, authorID: authorID)],
            projects: [ProjectDTO(id: projectID, title: "Thesis", summary: "Final project", notes: "Chapter 3", statusRaw: "active", priority: 1, targetDayKey: 300, colorHex: "#A855F7", sortOrder: 0, createdAt: fixedDate, completedAt: nil)],
            todos: [TodoDTO(id: todoID, title: "Write intro", notes: "Draft only", priority: 2, isDone: false, completedAt: nil, dayKey: 101, weekKey: nil, dueDayKey: 105, sortOrder: 0, createdAt: fixedDate, projectID: projectID)]
        )
    }

    /// Backups from before events could pick a colour carry no key for it.
    @Test func anEventWithoutAColourDecodesAsFollowingItsKind() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000005","title":"Interview","kindRaw":"interview"}"#
        let dto = try JSONDecoder().decode(EventDTO.self, from: Data(json.utf8))
        #expect(dto.colorHex == nil)
        #expect(dto.title == "Interview")
        // Same for shared groups: backups from before groups carry no key for either.
        #expect(dto.groupID == nil)
        #expect(dto.authorID == nil)
    }

    @Test func roundTripPreservesAFullyPopulatedDocument() throws {
        let original = fullDocument()
        let data = try original.encode()
        let decoded = try BackupDocument.decode(data)
        #expect(decoded == original)
    }

    @Test func encodedJSONIsPrettyPrintedWithSortedKeysAndVersion() throws {
        let data = try fullDocument().encode()
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"version\" : 1"))
        // Sorted keys: "blackouts" precedes "events" precedes "exceptions" alphabetically.
        let blackoutsIndex = json.range(of: "\"blackouts\"")!.lowerBound
        let eventsIndex = json.range(of: "\"events\"")!.lowerBound
        let exceptionsIndex = json.range(of: "\"exceptions\"")!.lowerBound
        #expect(blackoutsIndex < eventsIndex)
        #expect(eventsIndex < exceptionsIndex)
    }

    @Test func decodesMinimalHandWrittenJSON() throws {
        let json = """
        {
            "version": 1,
            "exportedAt": "2026-09-02T00:00:00.000Z",
            "terms": [],
            "series": [],
            "blackouts": [],
            "exceptions": [],
            "events": [],
            "projects": [],
            "todos": []
        }
        """
        let doc = try BackupDocument.decode(Data(json.utf8))
        #expect(doc.version == 1)
        #expect(doc.isEmpty)
        #expect(doc.entityCount == 0)
    }

    @Test func decodingTodoMissingOptionalAndArrayFieldsUsesDefaults() throws {
        let json = """
        {
            "version": 1,
            "exportedAt": "2026-09-02T00:00:00.000Z",
            "terms": [],
            "series": [],
            "blackouts": [{"id": "00000000-0000-0000-0000-000000000003", "startDayKey": 1, "endDayKey": 2, "reason": "no kinds"}],
            "exceptions": [],
            "events": [],
            "projects": [],
            "todos": [{"id": "00000000-0000-0000-0000-000000000007", "title": "Missing fields", "priority": 1, "isDone": false, "sortOrder": 0, "createdAt": "2026-09-02T00:00:00.000Z"}]
        }
        """
        let doc = try BackupDocument.decode(Data(json.utf8))
        let todo = try #require(doc.todos.first)
        #expect(todo.projectID == nil)
        #expect(todo.notes == "")

        let blackout = try #require(doc.blackouts.first)
        #expect(blackout.kindsRaw == [])
        #expect(blackout.termID == nil)
    }

    @Test func decodingUnsupportedVersionThrows() throws {
        let json = """
        {
            "version": 2,
            "exportedAt": "2026-09-02T00:00:00.000Z",
            "terms": [],
            "series": [],
            "blackouts": [],
            "exceptions": [],
            "events": [],
            "projects": [],
            "todos": []
        }
        """
        #expect(throws: BackupError.unsupportedVersion(2)) {
            try BackupDocument.decode(Data(json.utf8))
        }
    }

    @Test func decodingGarbageThrowsMalformed() {
        let garbage = Data("not json at all".utf8)
        #expect(throws: BackupError.self) {
            try BackupDocument.decode(garbage)
        }
        do {
            _ = try BackupDocument.decode(garbage)
            Issue.record("expected decode to throw")
        } catch let error as BackupError {
            guard case .malformed = error else {
                Issue.record("expected .malformed, got \(error)")
                return
            }
        } catch {
            Issue.record("expected BackupError, got \(error)")
        }
    }

    @Test func isEmptyAndEntityCount() {
        #expect(BackupDocument().isEmpty)
        #expect(BackupDocument().entityCount == 0)

        let doc = fullDocument()
        #expect(!doc.isEmpty)
        #expect(doc.entityCount == 7)
    }
}
