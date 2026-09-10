import Foundation

/// Local changes that have not reached the server yet: per table, which rows to upsert and which to
/// tombstone. A delete outranks an earlier upsert of the same row. Persisted as JSON so a change made
/// offline survives a relaunch.
nonisolated struct SyncOutbox: Codable, Sendable, Equatable {
    enum Operation: String, Codable, Sendable {
        case upsert, delete
    }

    private(set) var entries: [SyncTable: [UUID: Operation]] = [:]

    var isEmpty: Bool { entries.values.allSatisfy(\.isEmpty) }

    var count: Int { entries.values.reduce(0) { $0 + $1.count } }

    func operation(for id: UUID, in table: SyncTable) -> Operation? {
        entries[table]?[id]
    }

    /// Ids awaiting `operation` in `table`, in no particular order.
    func ids(in table: SyncTable, for operation: Operation) -> [UUID] {
        (entries[table] ?? [:]).filter { $0.value == operation }.map(\.key)
    }

    mutating func markUpsert(_ id: UUID, in table: SyncTable) {
        // A row deleted and re-inserted (undo) is an upsert again.
        entries[table, default: [:]][id] = .upsert
    }

    mutating func markDelete(_ id: UUID, in table: SyncTable) {
        entries[table, default: [:]][id] = .delete
    }

    /// Clears `id` only if it still carries `operation`: a change made while a push was in flight
    /// must not be wiped by that push's completion.
    mutating func clear(_ id: UUID, in table: SyncTable, ifStill operation: Operation) {
        guard entries[table]?[id] == operation else { return }
        entries[table]?[id] = nil
        if entries[table]?.isEmpty == true { entries[table] = nil }
    }

    mutating func removeAll() {
        entries = [:]
    }
}

/// Reads and writes the outbox file under Application Support. One instance per app; the tracker
/// and the sync service share it through `SyncTracker`.
@MainActor
final class SyncOutboxStore {
    private(set) var outbox: SyncOutbox
    private let url: URL

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return base.appending(path: "Sync", directoryHint: .isDirectory).appending(path: "outbox.json")
    }

    init(url: URL = SyncOutboxStore.defaultURL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(SyncOutbox.self, from: data) {
            outbox = decoded
        } else {
            outbox = SyncOutbox()
        }
    }

    func update(_ body: (inout SyncOutbox) -> Void) {
        var copy = outbox
        body(&copy)
        guard copy != outbox else { return }
        outbox = copy
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(outbox)
            try data.write(to: url, options: .atomic)
        } catch {
            print("SyncOutboxStore: could not write outbox: \(error)")
        }
    }
}
