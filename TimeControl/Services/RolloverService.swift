import Foundation
import SwiftData
import TimeControlCore

/// Carries unfinished todos forward. Anything still open on a day that has already passed lands on
/// today, so a missed day never silently buries work. Idempotent: running it twice moves nothing new.
@MainActor
enum RolloverService {
    /// `UserDefaults` key. A missing value means enabled.
    static let enabledKey = "rolloverEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Moves every open todo whose day is before `today` onto `today`, leaving week buckets untouched.
    /// Returns the todos that moved so callers can mark them in the UI. No-op when disabled.
    @discardableResult
    static func run(in context: ModelContext, today: DayKey = .today()) -> [TodoItem] {
        guard isEnabled else { return [] }
        let todayRaw = today.rawValue
        // SwiftData rejects `dayKey!` in a predicate ("the ForcedUnwrap operator is not supported"),
        // so todos with no day are coalesced to a key that can never read as past.
        let neverPast = Int.max
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate { !$0.isDone && ($0.dayKey ?? neverPast) < todayRaw }
        )
        guard let stale = try? context.fetch(descriptor), !stale.isEmpty else { return [] }
        for todo in stale {
            todo.day = today
        }
        try? context.save()
        return stale
    }
}
