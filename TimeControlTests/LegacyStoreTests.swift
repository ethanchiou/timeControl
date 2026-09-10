import Foundation
import SwiftData
import Testing
import TimeControlCore
@testable import TimeControl

/// Stores written by older models must keep opening. `Fixtures/legacy-v1.store` was written by the
/// first release's model (no colours, no groups, no sync fields); opening it exercises the automatic
/// lightweight migration the app relies on.
@Suite struct LegacyStoreTests {
    /// Copies a store file into a fresh temporary directory and returns the copy's URL.
    private func temporaryCopy(of store: URL) throws -> URL {
        let dir = URL.temporaryDirectory.appending(path: "legacy-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let copy = dir.appending(path: "TimeControl.store")
        try FileManager.default.copyItem(at: store, to: copy)
        for suffix in ["-wal", "-shm"] {
            let side = URL(fileURLWithPath: store.path + suffix)
            if FileManager.default.fileExists(atPath: side.path) {
                try FileManager.default.copyItem(at: side, to: URL(fileURLWithPath: copy.path + suffix))
            }
        }
        return copy
    }

    private var fixture: URL? {
        Bundle.allBundles
            .first { $0.bundleURL.lastPathComponent == "TimeControlTests.xctest" }?
            .url(forResource: "legacy-v1", withExtension: "store")
    }

    @Test func aFirstReleaseStoreOpensAndAcceptsNewRows() throws {
        let fixture = try #require(fixture, "legacy-v1.store must be bundled with the tests")
        let copy = try temporaryCopy(of: fixture)
        let container = try ModelContainerFactory.make(url: copy)
        let context = container.mainContext

        let terms = try context.fetch(FetchDescriptor<Term>())
        #expect(terms.isEmpty)

        let now = Date()
        let event = Event(title: "After migration", kind: .exam, start: now, end: now.addingTimeInterval(60), groupID: UUID())
        context.insert(event)
        context.insert(SharedGroup(uuid: UUID(), name: "g", colorHex: "#000000", joinCode: "ABCDEFGH", createdBy: UUID(), role: "owner"))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Event>()).first?.groupID == event.groupID)
        #expect(try context.fetch(FetchDescriptor<SharedGroup>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Event>()).first?.syncedAt == nil)
    }

    /// One-off check of a real store: `TEST_RUNNER_LEGACY_STORE=/path/to/TimeControl.store`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LEGACY_STORE"] != nil))
    func aGivenStoreOpens() throws {
        let path = try #require(ProcessInfo.processInfo.environment["LEGACY_STORE"])
        let copy = try temporaryCopy(of: URL(fileURLWithPath: path))
        let container = try ModelContainerFactory.make(url: copy)
        let context = container.mainContext
        let counts = (
            terms: try context.fetch(FetchDescriptor<Term>()).count,
            events: try context.fetch(FetchDescriptor<Event>()).count,
            todos: try context.fetch(FetchDescriptor<TodoItem>()).count
        )
        print("LegacyStoreTests: opened \(path): \(counts)")
        #expect(counts.terms >= 0)
    }
}
