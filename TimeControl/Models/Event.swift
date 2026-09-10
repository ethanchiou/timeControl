import Foundation
import SwiftData
import TimeControlCore

extension SchemaV2 {
    /// A one-off event: interview, exam, appointment.
    @Model
    final class Event {
        var uuid: UUID = UUID()
        var title: String = ""
        var kindRaw: String = Kind.other.rawValue
        var startDate: Date = Date()
        var endDate: Date = Date()
        var isAllDay: Bool = false
        var location: String = ""
        var notes: String = ""
        var reminderOffsetsMinutes: [Int] = []
        /// Hidden together with courses by the routine filter (gym, club meeting you added by hand).
        var isRoutine: Bool = false
        /// Overrides the kind's colour on the calendar; nil follows the kind. Ignored for a group
        /// event, which paints in its group's colour.
        var colorHex: String?
        /// The shared group this event belongs to; nil for a personal event.
        var groupID: UUID?
        /// Who created it, for group events; nil for a personal event or before the first sync.
        var authorID: UUID?
        var createdAt: Date = Date()
        /// The server's `updated_at` for the state last pushed or pulled; nil = never synced.
        var syncedAt: Date?

        init(title: String, kind: Kind, start: Date, end: Date, isAllDay: Bool = false, location: String = "", notes: String = "", reminderOffsetsMinutes: [Int]? = nil, isRoutine: Bool = false, groupID: UUID? = nil) {
            self.title = title
            self.kindRaw = kind.rawValue
            self.startDate = start
            self.endDate = max(end, start)
            self.isAllDay = isAllDay
            self.location = location
            self.notes = notes
            self.reminderOffsetsMinutes = reminderOffsetsMinutes ?? kind.defaultReminderMinutes.map { [$0] } ?? []
            self.isRoutine = isRoutine
            self.groupID = groupID
        }
    }
}

extension Event {
    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var day: DayKey { DayKey(startDate) }

    var isGroupEvent: Bool { groupID != nil }

    /// `groupColorHex` is the group's colour for the signed-in member; a group event paints in it
    /// instead of its own colour.
    func spec(groupColorHex: String? = nil) -> EventSpec {
        EventSpec(
            id: uuid,
            title: title,
            kind: kind,
            start: startDate,
            end: endDate,
            isAllDay: isAllDay,
            location: location,
            reminderOffsetsMinutes: reminderOffsetsMinutes,
            isRoutine: isRoutine,
            colorHex: groupID != nil ? (groupColorHex ?? colorHex) : colorHex,
            groupID: groupID
        )
    }

    var spec: EventSpec { spec(groupColorHex: nil) }
}
