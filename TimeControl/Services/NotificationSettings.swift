import Foundation
import TimeControlCore

/// UserDefaults-backed. All statics are MainActor-isolated for simplicity.
@MainActor
enum NotificationSettings {
    static let enabledKey = "notifications.enabled"
    static let todoDueHourKey = "notifications.todoDueHour"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private static func kindKey(_ kind: Kind) -> String { "notifications.kind.\(kind.rawValue)" }

    /// Missing → the kind's default lead time. Stored `-1` means "none".
    static func reminderMinutes(for kind: Kind) -> Int? {
        guard let stored = UserDefaults.standard.object(forKey: kindKey(kind)) as? Int else {
            return kind.defaultReminderMinutes
        }
        return stored == -1 ? nil : stored
    }

    static func setReminderMinutes(_ minutes: Int?, for kind: Kind) {
        UserDefaults.standard.set(minutes ?? -1, forKey: kindKey(kind))
    }

    /// Todos with a due day fire at this hour (0–23), local time.
    static var todoDueHour: Int {
        get { UserDefaults.standard.object(forKey: todoDueHourKey) as? Int ?? 9 }
        set { UserDefaults.standard.set(newValue, forKey: todoDueHourKey) }
    }

    static let reminderChoices: [Int?] = [nil, 0, 5, 10, 15, 30, 60, 120, 1440]

    static func label(forMinutes minutes: Int?) -> String {
        guard let minutes else { return "None" }
        if minutes == 0 { return "At time" }
        if minutes < 60 { return "\(minutes) minutes before" }
        if minutes < 1440 {
            let hours = minutes / 60
            return "\(hours) hour\(hours == 1 ? "" : "s") before"
        }
        let days = minutes / 1440
        return "\(days) day\(days == 1 ? "" : "s") before"
    }
}
