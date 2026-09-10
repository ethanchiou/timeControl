import Foundation
import SwiftData
import TimeControlCore

/// Watches every save on the main context and records what changed into the outbox, so the sync
/// service knows what to push without diffing the store. Rows written *by* the sync service (pulled
/// from the server) go through `applyingRemote`, which keeps them out of the outbox.
///
/// Only the parent of a cascade needs recording (the server cascades tombstones itself), but the
/// cascaded children land here too and their tombstones are harmless.
@MainActor
final class SyncTracker {
    static let shared = SyncTracker()

    let store: SyncOutboxStore
    private var observer: (any NSObjectProtocol)?
    private var context: ModelContext?
    private var isApplyingRemote = false
    /// Always on once started: changes made while signed out wait in the outbox for the next sign-in.
    var isEnabled = true

    init(store: SyncOutboxStore = SyncOutboxStore()) {
        self.store = store
    }

    var outbox: SyncOutbox { store.outbox }

    /// Watches saves of `context`, the app's main context. Saves of any other context are ignored.
    func start(context: ModelContext) {
        self.context = context
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: ModelContext.willSave, object: nil, queue: nil) { [weak self] notification in
            // willSave is posted synchronously by the saving context, so for the main context this
            // runs on the main actor. Only the sender's identity crosses into the isolated call.
            let sender = (notification.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                self?.record(sender: sender)
            }
        }
    }

    /// Runs `body` with tracking off, for writes that mirror the server rather than change it.
    /// Unsaved local edits are flushed first (tracked) so a save inside `body` cannot sweep them
    /// past the outbox.
    func applyingRemote<T>(in context: ModelContext, _ body: () throws -> T) rethrows -> T {
        if context.hasChanges, !isApplyingRemote {
            try? context.save()
        }
        let previous = isApplyingRemote
        isApplyingRemote = true
        defer {
            // Whatever `body` changed must be on disk before tracking resumes, or the next tracked
            // save would sweep it into the outbox as if it were a local edit.
            if !previous, context.hasChanges { try? context.save() }
            isApplyingRemote = previous
        }
        return try body()
    }

    private func record(sender: ObjectIdentifier?) {
        guard isEnabled, !isApplyingRemote, let context, sender == ObjectIdentifier(context) else { return }
        let inserted = context.insertedModelsArray.compactMap(Self.identify)
        let changed = context.changedModelsArray.compactMap(Self.identify)
        let deleted = context.deletedModelsArray.compactMap(Self.identify)
        guard !inserted.isEmpty || !changed.isEmpty || !deleted.isEmpty else { return }
        store.update { outbox in
            for (table, id) in inserted + changed { outbox.markUpsert(id, in: table) }
            for (table, id) in deleted { outbox.markDelete(id, in: table) }
        }
    }

    /// The synced table and row id of a model; nil for models that never sync as rows (groups).
    static func identify(_ model: any PersistentModel) -> (SyncTable, UUID)? {
        switch model {
        case let m as Term: (.terms, m.uuid)
        case let m as Series: (.series, m.uuid)
        case let m as Blackout: (.blackouts, m.uuid)
        case let m as OccurrenceException: (.occurrenceExceptions, m.uuid)
        case let m as Event: (.events, m.uuid)
        case let m as Project: (.projects, m.uuid)
        case let m as TodoItem: (.todos, m.uuid)
        default: nil
        }
    }
}
