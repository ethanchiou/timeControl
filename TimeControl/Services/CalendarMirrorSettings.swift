import Foundation
import TimeControlCore

/// UserDefaults-backed settings for the Apple Calendar mirror. All statics are MainActor-isolated,
/// matching `NotificationSettings`.
@MainActor
enum CalendarMirrorSettings {
    static let enabledKey = "calendarMirror.enabled"
    static let alarmsKey = "calendarMirror.alarms"
    static let lastSyncKey = "calendarMirror.lastSync"

    /// The mirror is opt-in: it writes to the user's calendar database, so it stays off until asked for.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private static func kindKey(_ kind: Kind) -> String { "calendarMirror.kind.\(kind.rawValue)" }

    /// Every kind mirrors by default except `.personal`, which is likelier to be private.
    static func isMirrored(_ kind: Kind) -> Bool {
        UserDefaults.standard.object(forKey: kindKey(kind)) as? Bool ?? (kind != .personal)
    }

    static func setMirrored(_ on: Bool, for kind: Kind) {
        UserDefaults.standard.set(on, forKey: kindKey(kind))
    }

    /// Whether mirrored events carry alarms. Lead times come from `Kind.defaultReminderMinutes`
    /// for series occurrences and from the event's own reminder offsets for one-off events.
    static var alarmsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: alarmsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: alarmsKey) }
    }

    static var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: lastSyncKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastSyncKey) }
    }

    /// Title of the calendar this app owns. Everything inside it is managed; nothing outside it is touched.
    static let calendarTitle = "TimeControl"

    /// Sync window, in days either side of today.
    static let pastDays = 7
    static let futureDays = 60
}
