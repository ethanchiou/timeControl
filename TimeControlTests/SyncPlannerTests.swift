import Foundation
import Testing
@testable import TimeControl

@Suite struct SyncPlannerTests {
    private let earlier = Date(timeIntervalSince1970: 1_000)
    private let later = Date(timeIntervalSince1970: 2_000)

    @Test func aPendingLocalChangeWins() {
        #expect(SyncPlanner.decide(pending: .upsert, localSyncedAt: earlier, remoteUpdatedAt: later, remoteDeleted: false) == .skip)
        #expect(SyncPlanner.decide(pending: .delete, localSyncedAt: earlier, remoteUpdatedAt: later, remoteDeleted: false) == .skip)
        // Even a remote tombstone waits: the local delete will land as its own tombstone.
        #expect(SyncPlanner.decide(pending: .upsert, localSyncedAt: nil, remoteUpdatedAt: later, remoteDeleted: true) == .skip)
    }

    @Test func aTombstoneDeletes() {
        #expect(SyncPlanner.decide(pending: nil, localSyncedAt: later, remoteUpdatedAt: earlier, remoteDeleted: true) == .delete)
        #expect(SyncPlanner.decide(pending: nil, localSyncedAt: nil, remoteUpdatedAt: nil, remoteDeleted: true) == .delete)
    }

    @Test func aReplayIsSkipped() {
        #expect(SyncPlanner.decide(pending: nil, localSyncedAt: later, remoteUpdatedAt: later, remoteDeleted: false) == .skip)
        #expect(SyncPlanner.decide(pending: nil, localSyncedAt: later, remoteUpdatedAt: earlier, remoteDeleted: false) == .skip)
    }

    @Test func anythingNewerApplies() {
        #expect(SyncPlanner.decide(pending: nil, localSyncedAt: earlier, remoteUpdatedAt: later, remoteDeleted: false) == .apply)
        #expect(SyncPlanner.decide(pending: nil, localSyncedAt: nil, remoteUpdatedAt: later, remoteDeleted: false) == .apply)
        #expect(SyncPlanner.decide(pending: nil, localSyncedAt: nil, remoteUpdatedAt: nil, remoteDeleted: false) == .apply)
    }

    @Test func pullStartsALittleBeforeTheCursor() {
        #expect(SyncPlanner.pullStart(cursor: nil) == nil)
        #expect(SyncPlanner.pullStart(cursor: later) == later.addingTimeInterval(-SyncPlanner.cursorOverlap))
    }
}
