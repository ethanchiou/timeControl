import Foundation

/// Errors from decoding a ``BackupDocument``.
public enum BackupError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case malformed(String)
}

/// A term (semester/quarter).
public struct TermDTO: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var startDayKey: Int
    public var endDayKey: Int
    public var isArchived: Bool

    public init(id: UUID = UUID(), name: String = "", startDayKey: Int = 0, endDayKey: Int = 0, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.startDayKey = startDayKey
        self.endDayKey = endDayKey
        self.isArchived = isArchived
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, startDayKey, endDayKey, isArchived
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        startDayKey = try c.decodeIfPresent(Int.self, forKey: .startDayKey) ?? 0
        endDayKey = try c.decodeIfPresent(Int.self, forKey: .endDayKey) ?? 0
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
}

/// A recurring course/meeting inside a term.
public struct SeriesDTO: Codable, Hashable, Sendable {
    public var id: UUID
    public var termID: UUID?
    public var title: String
    public var kindRaw: String
    public var weekdaysMask: Int
    public var startMinute: Int
    public var endMinute: Int
    public var intervalWeeks: Int
    public var startWeek: Int
    public var endWeek: Int
    public var location: String
    public var notes: String
    public var colorHex: String?

    public init(
        id: UUID = UUID(),
        termID: UUID? = nil,
        title: String = "",
        kindRaw: String = "",
        weekdaysMask: Int = 0,
        startMinute: Int = 0,
        endMinute: Int = 0,
        intervalWeeks: Int = 1,
        startWeek: Int = 1,
        endWeek: Int = 1,
        location: String = "",
        notes: String = "",
        colorHex: String? = nil
    ) {
        self.id = id
        self.termID = termID
        self.title = title
        self.kindRaw = kindRaw
        self.weekdaysMask = weekdaysMask
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.intervalWeeks = intervalWeeks
        self.startWeek = startWeek
        self.endWeek = endWeek
        self.location = location
        self.notes = notes
        self.colorHex = colorHex
    }

    private enum CodingKeys: String, CodingKey {
        case id, termID, title, kindRaw, weekdaysMask, startMinute, endMinute, intervalWeeks, startWeek, endWeek, location, notes, colorHex
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        termID = try c.decodeIfPresent(UUID.self, forKey: .termID)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        kindRaw = try c.decodeIfPresent(String.self, forKey: .kindRaw) ?? ""
        weekdaysMask = try c.decodeIfPresent(Int.self, forKey: .weekdaysMask) ?? 0
        startMinute = try c.decodeIfPresent(Int.self, forKey: .startMinute) ?? 0
        endMinute = try c.decodeIfPresent(Int.self, forKey: .endMinute) ?? 0
        intervalWeeks = try c.decodeIfPresent(Int.self, forKey: .intervalWeeks) ?? 1
        startWeek = try c.decodeIfPresent(Int.self, forKey: .startWeek) ?? 1
        endWeek = try c.decodeIfPresent(Int.self, forKey: .endWeek) ?? 1
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex)
    }
}

/// Suppresses recurring occurrences over a day range.
public struct BlackoutDTO: Codable, Hashable, Sendable {
    public var id: UUID
    public var termID: UUID?
    public var startDayKey: Int
    public var endDayKey: Int
    public var kindsRaw: [String]
    public var reason: String

    public init(id: UUID = UUID(), termID: UUID? = nil, startDayKey: Int = 0, endDayKey: Int = 0, kindsRaw: [String] = [], reason: String = "") {
        self.id = id
        self.termID = termID
        self.startDayKey = startDayKey
        self.endDayKey = endDayKey
        self.kindsRaw = kindsRaw
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case id, termID, startDayKey, endDayKey, kindsRaw, reason
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        termID = try c.decodeIfPresent(UUID.self, forKey: .termID)
        startDayKey = try c.decodeIfPresent(Int.self, forKey: .startDayKey) ?? 0
        endDayKey = try c.decodeIfPresent(Int.self, forKey: .endDayKey) ?? 0
        kindsRaw = try c.decodeIfPresent([String].self, forKey: .kindsRaw) ?? []
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
    }
}

/// A per-occurrence override of a series.
public struct ExceptionDTO: Codable, Hashable, Sendable {
    public var id: UUID
    public var seriesID: UUID?
    public var dayKey: Int
    public var kindRaw: String

    public init(id: UUID = UUID(), seriesID: UUID? = nil, dayKey: Int = 0, kindRaw: String = "") {
        self.id = id
        self.seriesID = seriesID
        self.dayKey = dayKey
        self.kindRaw = kindRaw
    }

    private enum CodingKeys: String, CodingKey {
        case id, seriesID, dayKey, kindRaw
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        seriesID = try c.decodeIfPresent(UUID.self, forKey: .seriesID)
        dayKey = try c.decodeIfPresent(Int.self, forKey: .dayKey) ?? 0
        kindRaw = try c.decodeIfPresent(String.self, forKey: .kindRaw) ?? ""
    }
}

/// A one-off event: interview, exam, appointment.
public struct EventDTO: Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var kindRaw: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var location: String
    public var notes: String
    public var reminderOffsetsMinutes: [Int]
    public var isRoutine: Bool
    /// Absent in backups written before events could pick a colour; nil follows the kind.
    public var colorHex: String?
    /// Absent in backups written before shared groups; nil is a personal event.
    public var groupID: UUID?
    /// Absent in backups written before shared groups; nil for a personal event or before the first sync.
    public var authorID: UUID?

    public init(
        id: UUID = UUID(),
        title: String = "",
        kindRaw: String = "",
        startDate: Date = Date(timeIntervalSince1970: 0),
        endDate: Date = Date(timeIntervalSince1970: 0),
        isAllDay: Bool = false,
        location: String = "",
        notes: String = "",
        reminderOffsetsMinutes: [Int] = [],
        isRoutine: Bool = false,
        colorHex: String? = nil,
        groupID: UUID? = nil,
        authorID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.kindRaw = kindRaw
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.reminderOffsetsMinutes = reminderOffsetsMinutes
        self.isRoutine = isRoutine
        self.colorHex = colorHex
        self.groupID = groupID
        self.authorID = authorID
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, kindRaw, startDate, endDate, isAllDay, location, notes, reminderOffsetsMinutes, isRoutine, colorHex, groupID, authorID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        kindRaw = try c.decodeIfPresent(String.self, forKey: .kindRaw) ?? ""
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate) ?? Date(timeIntervalSince1970: 0)
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate) ?? Date(timeIntervalSince1970: 0)
        isAllDay = try c.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        reminderOffsetsMinutes = try c.decodeIfPresent([Int].self, forKey: .reminderOffsetsMinutes) ?? []
        isRoutine = try c.decodeIfPresent(Bool.self, forKey: .isRoutine) ?? false
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex)
        groupID = try c.decodeIfPresent(UUID.self, forKey: .groupID)
        authorID = try c.decodeIfPresent(UUID.self, forKey: .authorID)
    }
}

/// A project (a container/backlog for todos).
public struct ProjectDTO: Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var summary: String
    public var notes: String
    public var statusRaw: String
    public var priority: Int
    public var targetDayKey: Int?
    public var colorHex: String
    public var sortOrder: Int
    public var createdAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String = "",
        summary: String = "",
        notes: String = "",
        statusRaw: String = "",
        priority: Int = 3,
        targetDayKey: Int? = nil,
        colorHex: String = "",
        sortOrder: Int = 0,
        createdAt: Date = Date(timeIntervalSince1970: 0),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.notes = notes
        self.statusRaw = statusRaw
        self.priority = priority
        self.targetDayKey = targetDayKey
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, summary, notes, statusRaw, priority, targetDayKey, colorHex, sortOrder, createdAt, completedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        statusRaw = try c.decodeIfPresent(String.self, forKey: .statusRaw) ?? ""
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 3
        targetDayKey = try c.decodeIfPresent(Int.self, forKey: .targetDayKey)
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? ""
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

/// A todo item.
public struct TodoDTO: Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var priority: Int
    public var isDone: Bool
    public var completedAt: Date?
    public var dayKey: Int?
    public var weekKey: Int?
    public var dueDayKey: Int?
    public var sortOrder: Int
    public var createdAt: Date
    public var projectID: UUID?

    public init(
        id: UUID = UUID(),
        title: String = "",
        notes: String = "",
        priority: Int = 3,
        isDone: Bool = false,
        completedAt: Date? = nil,
        dayKey: Int? = nil,
        weekKey: Int? = nil,
        dueDayKey: Int? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date(timeIntervalSince1970: 0),
        projectID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.priority = priority
        self.isDone = isDone
        self.completedAt = completedAt
        self.dayKey = dayKey
        self.weekKey = weekKey
        self.dueDayKey = dueDayKey
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.projectID = projectID
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, priority, isDone, completedAt, dayKey, weekKey, dueDayKey, sortOrder, createdAt, projectID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 3
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        dayKey = try c.decodeIfPresent(Int.self, forKey: .dayKey)
        weekKey = try c.decodeIfPresent(Int.self, forKey: .weekKey)
        dueDayKey = try c.decodeIfPresent(Int.self, forKey: .dueDayKey)
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        projectID = try c.decodeIfPresent(UUID.self, forKey: .projectID)
    }
}

/// JSON export/import document for the app's local-only data. Plain Codable DTOs that mirror the
/// app's SwiftData models field-for-field; the app maps to/from these.
public struct BackupDocument: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var exportedAt: Date
    public var terms: [TermDTO]
    public var series: [SeriesDTO]
    public var blackouts: [BlackoutDTO]
    public var exceptions: [ExceptionDTO]
    public var events: [EventDTO]
    public var projects: [ProjectDTO]
    public var todos: [TodoDTO]

    public init(
        exportedAt: Date = Date(),
        terms: [TermDTO] = [],
        series: [SeriesDTO] = [],
        blackouts: [BlackoutDTO] = [],
        exceptions: [ExceptionDTO] = [],
        events: [EventDTO] = [],
        projects: [ProjectDTO] = [],
        todos: [TodoDTO] = []
    ) {
        self.version = BackupDocument.currentVersion
        self.exportedAt = exportedAt
        self.terms = terms
        self.series = series
        self.blackouts = blackouts
        self.exceptions = exceptions
        self.events = events
        self.projects = projects
        self.todos = todos
    }

    /// Pretty-printed, sorted keys, ISO-8601 dates (with fractional seconds), so diffs are stable.
    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return try encoder.encode(self)
    }

    /// Throws ``BackupError/unsupportedVersion(_:)`` when the document's version is newer than
    /// ``currentVersion``. Any other decoding failure is wrapped in ``BackupError/malformed(_:)``.
    public static func decode(_ data: Data) throws -> BackupDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let strict = ISO8601DateFormatter()
            strict.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = strict.date(from: string) { return date }
            let lenient = ISO8601DateFormatter()
            lenient.formatOptions = [.withInternetDateTime]
            if let date = lenient.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(string)")
        }
        do {
            let document = try decoder.decode(BackupDocument.self, from: data)
            guard document.version <= currentVersion else {
                throw BackupError.unsupportedVersion(document.version)
            }
            return document
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.malformed(String(describing: error))
        }
    }

    public var isEmpty: Bool {
        terms.isEmpty && series.isEmpty && blackouts.isEmpty && exceptions.isEmpty
            && events.isEmpty && projects.isEmpty && todos.isEmpty
    }

    public var entityCount: Int {
        terms.count + series.count + blackouts.count + exceptions.count + events.count + projects.count + todos.count
    }
}
