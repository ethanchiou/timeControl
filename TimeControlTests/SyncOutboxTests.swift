import Foundation
import Testing
@testable import TimeControl

@Suite struct SyncOutboxTests {
    private let id = UUID()

    @Test func upsertThenDeleteLeavesADelete() {
        var outbox = SyncOutbox()
        outbox.markUpsert(id, in: .events)
        outbox.markDelete(id, in: .events)
        #expect(outbox.operation(for: id, in: .events) == .delete)
        #expect(outbox.ids(in: .events, for: .delete) == [id])
        #expect(outbox.ids(in: .events, for: .upsert).isEmpty)
    }

    @Test func deleteThenReinsertIsAnUpsertAgain() {
        var outbox = SyncOutbox()
        outbox.markDelete(id, in: .todos)
        outbox.markUpsert(id, in: .todos)
        #expect(outbox.operation(for: id, in: .todos) == .upsert)
    }

    @Test func clearOnlyRemovesTheOperationItWasToldAbout() {
        var outbox = SyncOutbox()
        outbox.markUpsert(id, in: .terms)
        // A delete landed while the upsert was in flight: completing the upsert must not wipe it.
        outbox.markDelete(id, in: .terms)
        outbox.clear(id, in: .terms, ifStill: .upsert)
        #expect(outbox.operation(for: id, in: .terms) == .delete)
        outbox.clear(id, in: .terms, ifStill: .delete)
        #expect(outbox.isEmpty)
    }

    @Test func tablesAreIndependent() {
        var outbox = SyncOutbox()
        outbox.markUpsert(id, in: .series)
        #expect(outbox.operation(for: id, in: .events) == nil)
        #expect(outbox.count == 1)
    }

    @Test func roundTripsThroughJSON() throws {
        var outbox = SyncOutbox()
        outbox.markUpsert(id, in: .occurrenceExceptions)
        outbox.markDelete(UUID(), in: .projects)
        let data = try JSONEncoder().encode(outbox)
        let decoded = try JSONDecoder().decode(SyncOutbox.self, from: data)
        #expect(decoded == outbox)
    }

    @Test func storePersistsAcrossInstances() throws {
        let url = URL.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = SyncOutboxStore(url: url)
        first.update { $0.markUpsert(id, in: .blackouts) }
        let second = SyncOutboxStore(url: url)
        #expect(second.outbox.operation(for: id, in: .blackouts) == .upsert)
    }

    @Test func pushOrderPutsParentsFirst() {
        let order = SyncTable.pushOrder
        #expect(order.firstIndex(of: .terms)! < order.firstIndex(of: .series)!)
        #expect(order.firstIndex(of: .series)! < order.firstIndex(of: .occurrenceExceptions)!)
        #expect(order.firstIndex(of: .projects)! < order.firstIndex(of: .todos)!)
        #expect(Set(order) == Set(SyncTable.allCases))
    }
}
