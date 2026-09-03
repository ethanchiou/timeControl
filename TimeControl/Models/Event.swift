import Foundation
import SwiftData
import TimeControlCore

extension SchemaV1 {
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
        var createdAt: Date = Date()

        init(title: String, kind: Kind, start: Date, end: Date, isAllDay: Bool = false, location: String = "", notes: String = "", reminderOffsetsMinutes: [Int]? = nil, isRoutine: Bool = false) {
            self.title = title
            self.kindRaw = kind.rawValue
            self.startDate = start
            self.endDate = max(end, start)
            self.isAllDay = isAllDay
            self.location = location
            self.notes = notes
            self.reminderOffsetsMinutes = reminderOffsetsMinutes ?? kind.defaultReminderMinutes.map { [$0] } ?? []
            self.isRoutine = isRoutine
        }
    }
}

extension Event {
    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var day: DayKey { DayKey(startDate) }

    var spec: EventSpec {
        EventSpec(id: uuid, title: title, kind: kind, start: startDate, end: endDate, isAllDay: isAllDay, location: location, reminderOffsetsMinutes: reminderOffsetsMinutes, isRoutine: isRoutine)
    }
}
