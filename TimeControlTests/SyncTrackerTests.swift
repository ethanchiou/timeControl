import Foundation
import SwiftData
import Testing
import TimeControlCore
@testable import TimeControl

@Suite struct SyncTrackerTests {
    private struct Store {
        let container: ModelContainer
        var context: ModelContext { container.mainContext }
        init() throws { container = try ModelContainerFactory.make(inMemory: true) }
    }

    private func makeTracker(_ store: Store) -> SyncTracker {
        let url = URL.temporaryDirectory.appending(path: "tracker-\(UUID().uuidString).json")
        let tracker = SyncTracker(store: SyncOutboxStore(url: url))
        tracker.start(context: store.context)
        return tracker
    }

    @Test func savesRecordInsertsChangesAndDeletes() throws {
        let store = try Store()
        let tracker = makeTracker(store)
        let now = Date()
        let event = Event(title: "A", kind: .other, start: now, end: now)
        store.context.insert(event)
        try store.context.save()
        #expect(tracker.outbox.operation(for: event.uuid, in: .events) == .upsert)

        tracker.store.update { $0.clear(event.uuid, in: .events, ifStill: .upsert) }
        event.title = "B"
        try store.context.save()
        #expect(tracker.outbox.operation(for: event.uuid, in: .events) == .upsert)

        store.context.delete(event)
        try store.context.save()
        #expect(tracker.outbox.operation(for: event.uuid, in: .events) == .delete)
    }

    @Test func remoteWritesStayOutOfTheOutbox() throws {
        let store = try Store()
        let tracker = makeTracker(store)
        let todo = TodoItem(title: "pulled")
        try tracker.applyingRemote(in: store.context) {
            store.context.insert(todo)
            try store.context.save()
        }
        #expect(tracker.outbox.isEmpty)
    }

    @Test func applyingRemoteFlushesPendingLocalEditsFirst() throws {
        let store = try Store()
        let tracker = makeTracker(store)
        let project = Project(title: "local")
        store.context.insert(project)
        // Not saved yet: the flush inside applyingRemote must record it before tracking goes off.
        try tracker.applyingRemote(in: store.context) {
            store.context.insert(TodoItem(title: "remote"))
            try store.context.save()
        }
        #expect(tracker.outbox.operation(for: project.uuid, in: .projects) == .upsert)
        #expect(tracker.outbox.count == 1)
    }

    @Test func groupsAreNotTracked() throws {
        let store = try Store()
        let tracker = makeTracker(store)
        store.context.insert(SharedGroup(uuid: UUID(), name: "g", colorHex: "#000000", joinCode: "X", createdBy: UUID(), role: "owner"))
        try store.context.save()
        #expect(tracker.outbox.isEmpty)
    }
}
