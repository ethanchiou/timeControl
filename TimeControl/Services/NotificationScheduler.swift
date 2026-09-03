import Foundation
import SwiftData
import UserNotifications
import TimeControlCore

/// Owns the app's local-notification lifecycle: authorization, and keeping the pending request set in
/// sync with the schedule. Every request this app schedules is identified with a "tc-" prefix so a
/// rebuild can safely wipe and replant its own notifications without touching anything else.
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private var debounceTask: Task<Void, Never>?

    private init() {}

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Requests `.alert`/`.sound`/`.badge` if not already determined. Returns whether notifications are
    /// authorized or provisional.
    @discardableResult
    func requestAuthorization() async -> Bool {
        #if DEBUG
        if CommandLine.arguments.contains("--no-permission-prompts") { return false }
        #endif
        await refreshAuthorizationStatus()
        if authorizationStatus == .notDetermined {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                print("NotificationScheduler: requestAuthorization failed: \(error)")
            }
            await refreshAuthorizationStatus()
        }
        return authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    /// Rebuilds every pending "tc-" notification request from the current schedule and open todos,
    /// looking ahead 30 days. No-op (beyond clearing existing "tc-" requests) when notifications are
    /// disabled in settings or not authorized.
    func reschedule(using context: ModelContext) async {
        let center = UNUserNotificationCenter.current()

        guard NotificationSettings.isEnabled else {
            await clearPending(center: center)
            return
        }
        await refreshAuthorizationStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
            await clearPending(center: center)
            return
        }

        let snapshot = ScheduleSnapshot.load(from: context)
        let today = DayKey.today()
        let occurrences = snapshot.occurrences(in: today...(today + 30), includeSuppressed: true)

        var eventOffsets: [UUID: [Int]] = [:]
        for event in snapshot.events {
            eventOffsets[event.id] = event.reminderOffsetsMinutes
        }

        let openTodos = (try? context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { !$0.isDone }))) ?? []
        let todoInputs: [TodoReminderInput] = openTodos.compactMap { todo in
            guard let dueDay = todo.dueDay else { return nil }
            return TodoReminderInput(id: todo.uuid, title: todo.title, dueDay: dueDay)
        }

        let planned = NotificationPlanner.plan(
            occurrences: occurrences,
            eventOffsets: eventOffsets,
            seriesReminder: { NotificationSettings.reminderMinutes(for: $0) },
            todos: todoInputs,
            todoDueHour: NotificationSettings.todoDueHour,
            now: Date(),
            calendar: .app
        )

        await clearPending(center: center)

        for notification in planned {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            content.threadIdentifier = notification.kind?.rawValue ?? "todo"
            if notification.kind == .exam || notification.kind == .interview {
                content.interruptionLevel = .timeSensitive
            }

            let comps = Calendar.app.dateComponents([.year, .month, .day, .hour, .minute, .second], from: notification.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                print("NotificationScheduler: failed to add \(notification.id): \(error)")
            }
        }
    }

    /// Debounced entry point for callers reacting to data changes: coalesces calls within 1.5 s.
    func scheduleRefresh(using context: ModelContext) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.reschedule(using: context)
        }
    }

    private func clearPending(center: UNUserNotificationCenter) async {
        let pending = await center.pendingNotificationRequests()
        let staleIDs = pending.map(\.identifier).filter { $0.hasPrefix("tc-") }
        center.removePendingNotificationRequests(withIdentifiers: staleIDs)
    }
}
