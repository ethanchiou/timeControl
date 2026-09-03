import Foundation
import TimeControlCore

/// One event as the mirror wants it to exist in Apple Calendar. Pure data: no `EventKit` import here.
struct MirrorEvent: Hashable, Sendable {
    /// The occurrence's stable id. Round-trips through `EKEvent.url` so a mirrored event can be
    /// matched back to the occurrence that produced it.
    var key: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String
    var notes: String
    /// Lead times in minutes before `start`. Empty means no alarms.
    var alarmMinutes: [Int]
    var kind: Kind

    static let managedNote = "Managed by TimeControl. Edits made here are overwritten on the next sync."

    static func url(for key: String) -> URL {
        let escaped = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        return URL(string: "timecontrol://occ/\(escaped)")!
    }

    /// The occurrence key carried by `url`, or nil when the URL is not one of ours.
    static func key(from url: URL?) -> String? {
        guard let url, url.scheme == "timecontrol", url.host() == "occ" else { return nil }
        let path = url.path(percentEncoded: false)
        let key = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return key.isEmpty ? nil : key
    }

    /// The fields the mirror actually writes to `EKEvent`. `notes` and `kind` are excluded: notes are
    /// constant, and kind is not readable back from an `EKEvent`.
    func matchesCalendarState(of other: MirrorEvent) -> Bool {
        title == other.title
            && start == other.start
            && end == other.end
            && isAllDay == other.isAllDay
            && location == other.location
            && alarmMinutes.sorted() == other.alarmMinutes.sorted()
    }
}

/// A mirrored event that already exists in the calendar, paired with its `EKEvent.eventIdentifier`.
struct ExistingMirrorEvent: Hashable, Sendable {
    var identifier: String
    var event: MirrorEvent
}

/// One event to rewrite in place.
struct MirrorUpdate: Hashable, Sendable {
    var identifier: String
    var event: MirrorEvent
}

/// The work needed to bring the calendar in line with the schedule.
struct MirrorDiff: Equatable, Sendable {
    var create: [MirrorEvent] = []
    var update: [MirrorUpdate] = []
    /// `EKEvent.eventIdentifier`s to remove.
    var delete: [String] = []

    var isEmpty: Bool { create.isEmpty && update.isEmpty && delete.isEmpty }
}

/// Turns occurrences into the set of calendar events the mirror should own, and diffs that against
/// what is already there.
///
/// Pure and side-effect free so it can be exhaustively unit tested: no `EventKit` import, no store
/// access, no `Date()` read internally.
enum CalendarMirrorPlanner {
    /// - Parameters:
    ///   - occurrences: Candidates for the sync window. Suppressed occurrences never mirror.
    ///   - mirroredKinds: Kinds the user has opted into; everything else is dropped.
    ///   - alarmsEnabled: Master switch. When false, no mirrored event carries an alarm.
    ///   - eventOffsets: Reminder lead times (minutes) per event id, from `EventSpec.reminderOffsetsMinutes`.
    ///   - calendar: Used to place all-day events at the start of their civil day.
    static func desired(
        occurrences: [Occurrence],
        mirroredKinds: Set<Kind>,
        alarmsEnabled: Bool,
        eventOffsets: [UUID: [Int]],
        calendar: Calendar = .app
    ) -> [MirrorEvent] {
        occurrences.compactMap { occurrence in
            guard !occurrence.isSuppressed, mirroredKinds.contains(occurrence.kind) else { return nil }

            let start = occurrence.isAllDay ? occurrence.day.startDate(in: calendar) : occurrence.start
            // EventKit reads all-day from the flag, not the span; a zero-length range keeps it to one day.
            let end = occurrence.isAllDay ? start : occurrence.end

            return MirrorEvent(
                key: occurrence.id,
                title: occurrence.title,
                start: start,
                end: end,
                isAllDay: occurrence.isAllDay,
                location: occurrence.location,
                notes: MirrorEvent.managedNote,
                alarmMinutes: alarms(for: occurrence, alarmsEnabled: alarmsEnabled, eventOffsets: eventOffsets),
                kind: occurrence.kind
            )
        }
    }

    private static func alarms(for occurrence: Occurrence, alarmsEnabled: Bool, eventOffsets: [UUID: [Int]]) -> [Int] {
        guard alarmsEnabled else { return [] }
        if let eventID = occurrence.eventID {
            return (eventOffsets[eventID] ?? []).sorted()
        }
        guard let minutes = occurrence.kind.defaultReminderMinutes else { return [] }
        return [minutes]
    }

    /// Matches desired against existing by key. Existing entries with an empty key are foreign
    /// (their `EKEvent.url` was not ours) and are left alone. Duplicates of a key — a half-committed
    /// sync — keep the lowest identifier and delete the rest. Output is sorted for determinism.
    static func diff(desired: [MirrorEvent], existing: [ExistingMirrorEvent]) -> MirrorDiff {
        var byKey: [String: [ExistingMirrorEvent]] = [:]
        for entry in existing where !entry.event.key.isEmpty {
            byKey[entry.event.key, default: []].append(entry)
        }

        var diff = MirrorDiff()

        for wanted in desired.sorted(by: { $0.key < $1.key }) {
            guard let matches = byKey.removeValue(forKey: wanted.key) else {
                diff.create.append(wanted)
                continue
            }
            let sorted = matches.sorted { $0.identifier < $1.identifier }
            let keeper = sorted[0]
            if !wanted.matchesCalendarState(of: keeper.event) {
                diff.update.append(MirrorUpdate(identifier: keeper.identifier, event: wanted))
            }
            diff.delete.append(contentsOf: sorted.dropFirst().map(\.identifier))
        }

        diff.delete.append(contentsOf: byKey.values.flatMap { $0 }.map(\.identifier))
        diff.delete.sort()
        return diff
    }
}
