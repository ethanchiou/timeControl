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
        /// event, which paints in the member's own colour for it or else its group's colour.
        var colorHex: String?
        /// The shared group this event belongs to; nil for a personal event.
        var groupID: UUID?
        /// Who created it, for group events; nil for a personal event or before the first sync.
        var authorID: UUID?
        /// Group events: one member finishing it finishes it for everyone. Off by default, because
        /// everyone having the same assignment due is not one submission.
        var sharedCompletion: Bool = false
        /// Set when a shared-completion event was finished, with the member who finished it.
        var completedAt: Date?
        var completedBy: UUID?
        /// The signed-in member's own colour for this group event, local only (the server keeps it in
        /// `event_member_states`, never in the event row). Nil follows the group's colour.
        var myColorHex: String?
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

    /// Routine events (gym, club) are habits, not tasks: nothing to finish and no todo to track them.
    var isCompletable: Bool { !isRoutine }

    /// Finishes or reopens a shared-completion event on behalf of `userID`. Individual completion
    /// lives on the member's linked todo instead; see `EventTaskLinker`.
    func setCompleted(_ done: Bool, by userID: UUID?) {
        completedAt = done ? (completedAt ?? Date()) : nil
        completedBy = done ? (completedBy ?? userID) : nil
    }

    /// Tagged with a kind other than `.other`. The tag is optional on an event; `.other` is "no tag".
    var isTagged: Bool { kind != .other }

    /// `groupColorHex` is the group's colour for the signed-in member. A group event paints in the
    /// member's own colour for it if they picked one; otherwise a tagged event follows its tag's
    /// colour (nil here, filled in by the snapshot from the member's kind presets) and an untagged one
    /// the group's. `isDone` is resolved by the caller from the member's linked todo or, for shared
    /// completion, from the event itself.
    func spec(groupColorHex: String? = nil, isDone: Bool = false) -> EventSpec {
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
            colorHex: groupID != nil ? (myColorHex ?? (isTagged ? nil : groupColorHex ?? colorHex)) : colorHex,
            groupID: groupID,
            isDone: isDone
        )
    }

    var spec: EventSpec { spec(groupColorHex: nil) }
}
