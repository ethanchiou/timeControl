import Foundation

/// The one decision the pull side makes per incoming row, kept pure so it can be tested flat.
///
/// A row with a pending local change is skipped: the local version wins until it has been pushed,
/// and the push overwrites the server. A tombstone deletes. Anything not newer than what this device
/// last synced is a replay (our own push echoed back, or an out-of-order realtime event) and is
/// skipped. Everything else is applied.
nonisolated enum SyncPlanner {
    enum Decision: Equatable, Sendable {
        case skip, delete, apply
    }

    static func decide(
        pending: SyncOutbox.Operation?,
        localSyncedAt: Date?,
        remoteUpdatedAt: Date?,
        remoteDeleted: Bool
    ) -> Decision {
        if pending != nil { return .skip }
        if remoteDeleted { return .delete }
        if let local = localSyncedAt, let remote = remoteUpdatedAt, remote <= local { return .skip }
        return .apply
    }

    /// Re-pull from a little before the cursor: rows committed out of `updated_at` order around it
    /// would otherwise be missed, and re-applying a row is harmless.
    static let cursorOverlap: TimeInterval = 5

    /// Rows per page.
    static let pageSize = 500

    static func pullStart(cursor: Date?) -> Date? {
        cursor.map { $0.addingTimeInterval(-cursorOverlap) }
    }
}
