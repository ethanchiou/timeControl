import Foundation
import TimeControlCore

// Wire types for the Supabase tables, one per table, snake_case on the wire via `SupabaseCoding`.
//
// Decoding is synthesized. Encoding is written out so that every nullable column is sent, `null`
// included: an upsert only touches the columns present in the payload, so leaving `deleted_at` or
// `group_id` out would keep a stale value on the server. `updated_at` is never sent; the server stamps it.

/// What every synced row shares. `updatedAt` comes back from the server; `deletedAt` is the tombstone.
nonisolated protocol SyncRow: Codable, Sendable, Identifiable where ID == UUID {
    static var table: SyncTable { get }
    var id: UUID { get }
    var updatedAt: Date? { get }
    var deletedAt: Date? { get }
}

/// The synced tables in push order: parents before children so foreign keys hold.
nonisolated enum SyncTable: String, CaseIterable, Codable, Sendable {
    case terms, series, blackouts, occurrenceExceptions = "occurrence_exceptions", events, projects, todos

    /// Parents first.
    static let pushOrder: [SyncTable] = [.terms, .series, .blackouts, .occurrenceExceptions, .projects, .todos, .events]
}

nonisolated struct TermRow: SyncRow {
    static let table = SyncTable.terms
    var id: UUID
    var userId: UUID
    var name: String
    var startDayKey: Int
    var endDayKey: Int
    var isArchived: Bool
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, userId, name, startDayKey, endDayKey, isArchived, createdAt, updatedAt, deletedAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encode(name, forKey: .name)
        try c.encode(startDayKey, forKey: .startDayKey)
        try c.encode(endDayKey, forKey: .endDayKey)
        try c.encode(isArchived, forKey: .isArchived)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

nonisolated struct SeriesRow: SyncRow {
    static let table = SyncTable.series
    var id: UUID
    var userId: UUID
    var termId: UUID?
    var title: String
    var kind: String
    var weekdaysMask: Int
    var startMinute: Int
    var endMinute: Int
    var intervalWeeks: Int
    var startWeek: Int
    var endWeek: Int
    var location: String
    var notes: String
    var colorHex: String?
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, userId, termId, title, kind, weekdaysMask, startMinute, endMinute, intervalWeeks, startWeek, endWeek, location, notes, colorHex, createdAt, updatedAt, deletedAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encode(termId, forKey: .termId)
        try c.encode(title, forKey: .title)
        try c.encode(kind, forKey: .kind)
        try c.encode(weekdaysMask, forKey: .weekdaysMask)
        try c.encode(startMinute, forKey: .startMinute)
        try c.encode(endMinute, forKey: .endMinute)
        try c.encode(intervalWeeks, forKey: .intervalWeeks)
        try c.encode(startWeek, forKey: .startWeek)
        try c.encode(endWeek, forKey: .endWeek)
        try c.encode(location, forKey: .location)
        try c.encode(notes, forKey: .notes)
        try c.encode(colorHex, forKey: .colorHex)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

nonisolated struct BlackoutRow: SyncRow {
    static let table = SyncTable.blackouts
    var id: UUID
    var userId: UUID
    var termId: UUID?
    var startDayKey: Int
    var endDayKey: Int
    var kinds: [String]
    var reason: String
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, userId, termId, startDayKey, endDayKey, kinds, reason, createdAt, updatedAt, deletedAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encode(termId, forKey: .termId)
        try c.encode(startDayKey, forKey: .startDayKey)
        try c.encode(endDayKey, forKey: .endDayKey)
        try c.encode(kinds, forKey: .kinds)
        try c.encode(reason, forKey: .reason)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

nonisolated struct ExceptionRow: SyncRow {
    static let table = SyncTable.occurrenceExceptions
    var id: UUID
    var userId: UUID
    var seriesId: UUID?
    var dayKey: Int
    var kind: String
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, userId, seriesId, dayKey, kind, createdAt, updatedAt, deletedAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encode(seriesId, forKey: .seriesId)
        try c.encode(dayKey, forKey: .dayKey)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

nonisolated struct EventRow: SyncRow {
    static let table = SyncTable.events
    var id: UUID
    /// The author; immutable on the server.
    var userId: UUID
    var groupId: UUID?
    var title: String
    var kind: String
    var startAt: Date
    var endAt: Date
    var isAllDay: Bool
    var location: String
    var notes: String
    var reminderOffsetsMinutes: [Int]
    var isRoutine: Bool
    var colorHex: String?
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, userId, groupId, title, kind, startAt, endAt, isAllDay, location, notes, reminderOffsetsMinutes, isRoutine, colorHex, createdAt, updatedAt, deletedAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encode(groupId, forKey: .groupId)
        try c.encode(title, forKey: .title)
        try c.encode(kind, forKey: .kind)
        try c.encode(startAt, forKey: .startAt)
        try c.encode(endAt, forKey: .endAt)
        try c.encode(isAllDay, forKey: .isAllDay)
        try c.encode(location, forKey: .location)
        try c.encode(notes, forKey: .notes)
        try c.encode(reminderOffsetsMinutes, forKey: .reminderOffsetsMinutes)
        try c.encode(isRoutine, forKey: .isRoutine)
        try c.encode(colorHex, forKey: .colorHex)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

nonisolated struct ProjectRow: SyncRow {
    static let table = SyncTable.projects
    var id: UUID
    var userId: UUID
    var title: String
    var summary: String
    var notes: String
    var status: String
    var priority: Int
    var targetDayKey: Int?
    var colorHex: String
    var sortOrder: Int
    var completedAt: Date?
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, userId, title, summary, notes, status, priority, targetDayKey, colorHex, sortOrder, completedAt, createdAt, updatedAt, deletedAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encode(title, forKey: .title)
        try c.encode(summary, forKey: .summary)
        try c.encode(notes, forKey: .notes)
        try c.encode(status, forKey: .status)
        try c.encode(priority, forKey: .priority)
        try c.encode(targetDayKey, forKey: .targetDayKey)
        try c.encode(colorHex, forKey: .colorHex)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(completedAt, forKey: .completedAt)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

nonisolated struct TodoItemRow: SyncRow {
    static let table = SyncTable.todos
    var id: UUID
    var userId: UUID
    var projectId: UUID?
    var title: String
    var notes: String
    var priority: Int
    var isDone: Bool
    var completedAt: Date?
    var dayKey: Int?
    var weekKey: Int?
    var dueDayKey: Int?
    var sortOrder: Int
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, userId, projectId, title, notes, priority, isDone, completedAt, dayKey, weekKey, dueDayKey, sortOrder, createdAt, updatedAt, deletedAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encode(projectId, forKey: .projectId)
        try c.encode(title, forKey: .title)
        try c.encode(notes, forKey: .notes)
        try c.encode(priority, forKey: .priority)
        try c.encode(isDone, forKey: .isDone)
        try c.encode(completedAt, forKey: .completedAt)
        try c.encode(dayKey, forKey: .dayKey)
        try c.encode(weekKey, forKey: .weekKey)
        try c.encode(dueDayKey, forKey: .dueDayKey)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

// MARK: Groups (pulled, never pushed as rows; writes go through RPCs and the member row)

nonisolated struct GroupRow: Codable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var colorHex: String
    var joinCode: String
    var createdBy: UUID
    var createdAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?
}

/// A `group_members` row joined with the member's profile: `select *, profiles(display_name)`.
nonisolated struct GroupMemberRow: Codable, Sendable {
    nonisolated struct Profile: Codable, Sendable {
        var displayName: String
    }

    var groupId: UUID
    var userId: UUID
    var role: String
    var colorOverrideHex: String?
    var joinedAt: Date?
    var updatedAt: Date?
    var profiles: Profile?
}

nonisolated struct ProfileRow: Codable, Sendable, Identifiable {
    var id: UUID
    var displayName: String
    var updatedAt: Date?
}
