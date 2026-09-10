import Foundation
import SwiftData
import Testing
import TimeControlCore
@testable import TimeControl

@Suite struct SyncMappingTests {
    private struct Store {
        let container: ModelContainer
        var context: ModelContext { container.mainContext }
        init() throws { container = try ModelContainerFactory.make(inMemory: true) }
    }

    private let userID = UUID()

    @Test func eventRowRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let groupID = UUID()
        let event = Event(title: "Exam", kind: .exam, start: now, end: now.addingTimeInterval(7200), isAllDay: false, location: "Hall", notes: "bring id", reminderOffsetsMinutes: [60, 10], isRoutine: false, groupID: groupID)
        event.colorHex = "#E5484D"

        let row = event.row(userID: userID)
        #expect(row.userId == userID, "a never-synced event is authored by whoever pushes it")
        #expect(row.groupId == groupID)
        #expect(row.kind == "exam")

        let rebuilt = Event.make(from: row)
        #expect(rebuilt.uuid == event.uuid)
        #expect(rebuilt.title == "Exam")
        #expect(rebuilt.reminderOffsetsMinutes == [60, 10])
        #expect(rebuilt.groupID == groupID)
        #expect(rebuilt.authorID == userID)
        #expect(rebuilt.colorHex == "#E5484D")

        // A pulled group event keeps its author when this device pushes an edit.
        let other = UUID()
        var pulled = row
        pulled.userId = other
        rebuilt.apply(pulled)
        #expect(rebuilt.row(userID: userID).userId == other)
    }

    @Test func nullableColumnsAreSentExplicitly() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let event = Event(title: "Plain", kind: .other, start: now, end: now)
        let data = try SupabaseCoding.encoder.encode(event.row(userID: userID))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["deleted_at"] is NSNull)
        #expect(json["group_id"] is NSNull)
        #expect(json["color_hex"] is NSNull)
        #expect(json["updated_at"] == nil, "the server stamps updated_at")
        #expect(json["is_all_day"] as? Bool == false)
        #expect(json["start_at"] is String)
    }

    @Test func seriesResolvesItsTermOnApply() throws {
        let store = try Store()
        let term = Term(name: "Fall", start: DayKey(year: 2026, month: 9, day: 1), end: DayKey(year: 2026, month: 12, day: 15))
        store.context.insert(term)
        let row = SeriesRow(id: UUID(), userId: userID, termId: term.uuid, title: "CS201", kind: "course", weekdaysMask: Weekday.mask(of: [.monday]), startMinute: 600, endMinute: 660, intervalWeeks: 1, startWeek: 1, endWeek: 14, location: "", notes: "", colorHex: nil, createdAt: nil, updatedAt: Date(), deletedAt: nil)
        let series = Series.make(from: row, in: store.context)
        #expect(series.term?.uuid == term.uuid)
        #expect(series.spec != nil)
        #expect(series.syncedAt != nil)
    }

    @Test func anExceptionWithoutItsSeriesIsNotCreated() throws {
        let store = try Store()
        let row = ExceptionRow(id: UUID(), userId: userID, seriesId: UUID(), dayKey: 0, kind: "skipped", createdAt: nil, updatedAt: nil, deletedAt: nil)
        #expect(OccurrenceException.make(from: row, in: store.context) == nil)
    }

    @Test func postgresTimestampsDecode() throws {
        struct Probe: Decodable { let at: Date }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let expected = try #require(utc.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 2, minute: 26, second: 16)))

        let sixDigits = Data(#"{"at":"2026-09-10T02:26:16.953598+00:00"}"#.utf8)
        let decoded = try SupabaseCoding.decoder.decode(Probe.self, from: sixDigits)
        #expect(abs(decoded.at.timeIntervalSince(expected) - 0.953) < 0.01)

        let whole = Data(#"{"at":"2026-09-10T02:26:16Z"}"#.utf8)
        #expect(try SupabaseCoding.decoder.decode(Probe.self, from: whole).at == expected)

        let threeDigits = Data(#"{"at":"2026-09-10T02:26:16.953Z"}"#.utf8)
        #expect(abs(try SupabaseCoding.decoder.decode(Probe.self, from: threeDigits).at.timeIntervalSince(expected) - 0.953) < 0.001)
    }
}
