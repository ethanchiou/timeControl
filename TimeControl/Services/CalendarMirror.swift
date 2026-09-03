import CoreGraphics
import EventKit
import Foundation
import SwiftData
import TimeControlCore

/// Mirrors the schedule into a dedicated "TimeControl" calendar in Apple Calendar, so courses and
/// events show up on every device the user's calendar account reaches.
///
/// The app owns that one calendar and nothing else: every event it writes carries a
/// `timecontrol://occ/<key>` URL, and only events carrying such a URL are ever updated or deleted.
/// `EKEventStore` is not `Sendable`, so the whole class stays on the main actor.
@MainActor
final class CalendarMirror {
    static let shared = CalendarMirror()

    struct Summary: Equatable {
        var created: Int
        var updated: Int
        var deleted: Int

        static let none = Summary(created: 0, updated: 0, deleted: 0)
        var isEmpty: Bool { self == .none }
    }

    enum MirrorError: Error, LocalizedError {
        case accessDenied
        case noSource
        case eventKit(String)

        var errorDescription: String? {
            switch self {
            case .accessDenied: "TimeControl needs full access to your calendars to mirror your schedule."
            case .noSource: "No calendar account is available to hold the TimeControl calendar."
            case .eventKit(let message): message
            }
        }
    }

    private let store = EKEventStore()
    private var debounceTask: Task<Void, Never>?

    private(set) var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    private init() {}

    func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    /// Prompts for full calendar access if it has not been decided yet. Returns whether full access
    /// is granted.
    @discardableResult
    func requestAccess() async -> Bool {
        var granted = false
        do {
            granted = try await store.requestFullAccessToEvents()
        } catch {
            print("CalendarMirror: requestFullAccessToEvents failed: \(error)")
        }
        refreshAuthorizationStatus()
        return granted
    }

    // MARK: Sync

    /// Brings the mirror calendar in line with the schedule over `[today − pastDays, today + futureDays]`.
    /// No-op when the mirror is switched off; throws when access has not been granted.
    @discardableResult
    func sync(using context: ModelContext) async throws -> Summary {
        guard CalendarMirrorSettings.isEnabled else { return .none }
        refreshAuthorizationStatus()
        guard authorizationStatus == .fullAccess else { throw MirrorError.accessDenied }

        let calendar = try mirrorCalendar()
        let days = syncWindow()

        let snapshot = ScheduleSnapshot.load(from: context)
        var eventOffsets: [UUID: [Int]] = [:]
        for event in snapshot.events {
            eventOffsets[event.id] = event.reminderOffsetsMinutes
        }
        let desired = CalendarMirrorPlanner.desired(
            occurrences: snapshot.occurrences(in: days),
            mirroredKinds: Set(Kind.allCases.filter { CalendarMirrorSettings.isMirrored($0) }),
            alarmsEnabled: CalendarMirrorSettings.alarmsEnabled,
            eventOffsets: eventOffsets
        )

        var byIdentifier: [String: EKEvent] = [:]
        var existing: [ExistingMirrorEvent] = []
        for ekEvent in events(in: days, calendar: calendar) {
            guard let key = MirrorEvent.key(from: ekEvent.url), let identifier = ekEvent.eventIdentifier else { continue }
            byIdentifier[identifier] = ekEvent
            existing.append(ExistingMirrorEvent(identifier: identifier, event: mirrorEvent(from: ekEvent, key: key)))
        }

        let diff = CalendarMirrorPlanner.diff(desired: desired, existing: existing)
        var summary = Summary.none
        do {
            for event in diff.create {
                let ekEvent = EKEvent(eventStore: store)
                apply(event, to: ekEvent, calendar: calendar)
                try store.save(ekEvent, span: .thisEvent, commit: false)
                summary.created += 1
            }
            for update in diff.update {
                guard let ekEvent = byIdentifier[update.identifier] else { continue }
                apply(update.event, to: ekEvent, calendar: calendar)
                try store.save(ekEvent, span: .thisEvent, commit: false)
                summary.updated += 1
            }
            for identifier in diff.delete {
                guard let ekEvent = byIdentifier[identifier] else { continue }
                try store.remove(ekEvent, span: .thisEvent, commit: false)
                summary.deleted += 1
            }
            try store.commit()
        } catch {
            store.reset()
            throw MirrorError.eventKit(error.localizedDescription)
        }

        CalendarMirrorSettings.lastSyncDate = Date()
        return summary
    }

    /// Debounced entry point for callers reacting to data changes: coalesces calls within 2 s.
    func scheduleSync(using context: ModelContext) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            do {
                _ = try await self?.sync(using: context)
            } catch {
                print("CalendarMirror: sync failed: \(error)")
            }
        }
    }

    /// Removes every event the mirror owns in the sync window, and optionally the calendar itself.
    /// Used when the user switches the mirror off.
    func removeAll(deleteCalendar: Bool) async throws {
        refreshAuthorizationStatus()
        guard authorizationStatus == .fullAccess else { throw MirrorError.accessDenied }
        guard let calendar = findMirrorCalendar() else { return }

        do {
            for ekEvent in events(in: syncWindow(), calendar: calendar) where MirrorEvent.key(from: ekEvent.url) != nil {
                try store.remove(ekEvent, span: .thisEvent, commit: false)
            }
            if deleteCalendar {
                try store.removeCalendar(calendar, commit: false)
            }
            try store.commit()
        } catch {
            store.reset()
            throw MirrorError.eventKit(error.localizedDescription)
        }
    }

    // MARK: Calendar

    private func syncWindow() -> ClosedRange<DayKey> {
        let today = DayKey.today()
        return (today - CalendarMirrorSettings.pastDays)...(today + CalendarMirrorSettings.futureDays)
    }

    /// The app's calendar, matched by title.
    private func findMirrorCalendar() -> EKCalendar? {
        store.calendars(for: .event).first { $0.title == CalendarMirrorSettings.calendarTitle }
    }

    /// The app's calendar, created in the default account if it is not there yet.
    private func mirrorCalendar() throws -> EKCalendar {
        if let existing = findMirrorCalendar() { return existing }

        guard let source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first(where: { $0.sourceType == .local })
            ?? store.sources.first
        else { throw MirrorError.noSource }

        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = CalendarMirrorSettings.calendarTitle
        calendar.source = source
        calendar.cgColor = CalendarMirror.cgColor(hex: Kind.course.colorHex)
        do {
            try store.saveCalendar(calendar, commit: true)
        } catch {
            store.reset()
            throw MirrorError.eventKit(error.localizedDescription)
        }
        return calendar
    }

    private func events(in days: ClosedRange<DayKey>, calendar: EKCalendar) -> [EKEvent] {
        let predicate = store.predicateForEvents(
            withStart: days.lowerBound.startDate(),
            end: (days.upperBound + 1).startDate(),
            calendars: [calendar]
        )
        return store.events(matching: predicate)
    }

    // MARK: EKEvent conversion

    private func mirrorEvent(from ekEvent: EKEvent, key: String) -> MirrorEvent {
        let isAllDay = ekEvent.isAllDay
        let start = ekEvent.startDate ?? Date()
        let alarms = (ekEvent.alarms ?? [])
            .filter { $0.absoluteDate == nil }
            .map { Int((-$0.relativeOffset / 60).rounded()) }
            .sorted()
        return MirrorEvent(
            key: key,
            title: ekEvent.title ?? "",
            start: start,
            // All-day events are written zero-length; EventKit may normalize the end date, so read it
            // back the way it was written rather than churning an update on every sync.
            end: isAllDay ? start : (ekEvent.endDate ?? start),
            isAllDay: isAllDay,
            location: ekEvent.location ?? "",
            notes: MirrorEvent.managedNote,
            alarmMinutes: alarms,
            // Kind is not stored in EventKit; the diff never compares it.
            kind: .other
        )
    }

    private func apply(_ event: MirrorEvent, to ekEvent: EKEvent, calendar: EKCalendar) {
        ekEvent.calendar = calendar
        ekEvent.title = event.title
        ekEvent.startDate = event.start
        ekEvent.endDate = event.isAllDay ? event.start : event.end
        ekEvent.isAllDay = event.isAllDay
        ekEvent.location = event.location.isEmpty ? nil : event.location
        ekEvent.notes = event.notes
        ekEvent.url = MirrorEvent.url(for: event.key)
        ekEvent.alarms = event.alarmMinutes.map { EKAlarm(relativeOffset: -Double($0) * 60) }
    }

    /// "#RRGGBB" → sRGB. Falls back to grey for malformed input.
    private static func cgColor(hex: String) -> CGColor {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            return CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        }
        return CGColor(
            srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }
}
