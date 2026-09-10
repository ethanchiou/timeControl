import Foundation
import Observation
import Supabase
import SwiftData
import TimeControlCore

/// Keeps the local store and the account's rows on the server the same.
///
/// Push: whatever `SyncTracker` put in the outbox, parents before children, upserted by id; deletes
/// become tombstones. Pull: per table, everything with `updated_at` past this device's cursor,
/// tombstones included, decided row by row by `SyncPlanner`. Runs after every save (debounced), on
/// launch and foreground, on sign-in, and whenever the realtime channel reports a change.
///
/// Signed out, the app is local-only and nothing here runs; the outbox keeps collecting so the next
/// sign-in pushes what changed meanwhile.
@MainActor
@Observable
final class SyncService {
    static let shared = SyncService()

    enum Status: Equatable, Sendable {
        /// No account: local-only.
        case off
        case idle
        case syncing
        case failed(String)
    }

    private(set) var status: Status = .off
    private(set) var lastSyncDate: Date?
    var pendingCount: Int { tracker.outbox.count }

    private let client: SupabaseClient?
    private let auth: AuthService
    private let tracker: SyncTracker
    private let groups: GroupService
    private var container: ModelContainer?
    private var currentUserID: UUID?
    private var needsReconcile = false
    private var isSyncing = false
    private var syncRequestedAgain = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Distinguishes several stores in one process (tests); the app uses the default.
    private let instanceKey: String
    /// Tests switch the realtime channel off to keep runs deterministic.
    var isRealtimeEnabled = true
    private var debounceTask: Task<Void, Never>?
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTasks: [Task<Void, Never>] = []
    private var authTask: Task<Void, Never>?

    init(
        client: SupabaseClient? = SupabaseClientProvider.shared,
        auth: AuthService = .shared,
        tracker: SyncTracker = .shared,
        groups: GroupService = .shared,
        instanceKey: String = ""
    ) {
        self.client = client
        self.auth = auth
        self.tracker = tracker
        self.groups = groups
        self.instanceKey = instanceKey
    }

    var isAvailable: Bool { client != nil }

    // MARK: Lifecycle

    /// Call once from the root view with the app's container.
    func start(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        tracker.start(context: container.mainContext)
        auth.start()
        handle(authState: auth.state)
        let changes = auth.stateChanges
        authTask = Task { [weak self] in
            for await state in changes {
                self?.handle(authState: state)
            }
        }
    }

    private func handle(authState: AuthService.State) {
        switch authState {
        case .signedIn(let userID, _):
            guard currentUserID != userID else { return }
            currentUserID = userID
            if lastUserID != userID {
                // A different account than last time: everything local is new to it.
                resetSyncedAt()
                lastUserID = userID
            }
            needsReconcile = true
            status = .idle
            startRealtime()
            Task { await syncNow() }
        case .signedOut, .unavailable:
            guard currentUserID != nil else {
                status = .off
                return
            }
            let leaving = currentUserID
            currentUserID = nil
            stopRealtime()
            debounceTask?.cancel()
            status = .off
            purgeSharedData(exceptAuthor: leaving)
        }
    }

    /// Debounced entry point for callers reacting to data changes: coalesces calls within 2 s.
    func scheduleSync() {
        guard currentUserID != nil else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// One full push-then-pull. A call made while one is running queues exactly one more pass and
    /// returns when that pass is done, so callers can rely on "after `syncNow`, we are in sync".
    func syncNow() async {
        guard client != nil, container != nil, currentUserID != nil else { return }
        if isSyncing {
            syncRequestedAgain = true
            await withCheckedContinuation { waiters.append($0) }
            return
        }
        isSyncing = true
        repeat {
            syncRequestedAgain = false
            await runOnce()
        } while syncRequestedAgain && currentUserID != nil
        isSyncing = false
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter.resume() }
    }

    private func runOnce() async {
        guard let client, let container, let userID = currentUserID else { return }
        let context = container.mainContext
        status = .syncing
        do {
            await groups.refresh(into: context)
            if needsReconcile {
                try enqueueNeverSynced(in: context)
                needsReconcile = false
            }
            try await push(client: client, context: context, userID: userID)
            try await pullAll(client: client, context: context, userID: userID)
            lastSyncDate = Date()
            status = .idle
        } catch {
            status = .failed(Self.describe(error))
            print("SyncService: sync failed: \(error)")
        }
    }

    // MARK: Push

    private func push(client: SupabaseClient, context: ModelContext, userID: UUID) async throws {
        for table in SyncTable.pushOrder {
            let outbox = tracker.outbox
            let upserts = outbox.ids(in: table, for: .upsert)
            let deletes = outbox.ids(in: table, for: .delete)
            if !upserts.isEmpty {
                try await pushUpserts(table, ids: upserts, client: client, context: context, userID: userID)
            }
            if !deletes.isEmpty {
                try await pushDeletes(table, ids: deletes, client: client)
            }
        }
    }

    private func pushUpserts(_ table: SyncTable, ids: [UUID], client: SupabaseClient, context: ModelContext, userID: UUID) async throws {
        let stamps: [SyncStamp]
        var found: Set<UUID> = []
        switch table {
        case .terms:
            let models = ids.compactMap { context.term(uuid: $0) }
            found = Set(models.map(\.uuid))
            stamps = try await upsert(models.map { $0.row(userID: userID) }, table: table, client: client)
            apply(stamps, to: models, context: context)
        case .series:
            let models = ids.compactMap { context.series(uuid: $0) }
            found = Set(models.map(\.uuid))
            stamps = try await upsert(models.map { $0.row(userID: userID) }, table: table, client: client)
            apply(stamps, to: models, context: context)
        case .blackouts:
            let models = ids.compactMap { context.blackout(uuid: $0) }
            found = Set(models.map(\.uuid))
            stamps = try await upsert(models.map { $0.row(userID: userID) }, table: table, client: client)
            apply(stamps, to: models, context: context)
        case .occurrenceExceptions:
            let models = ids.compactMap { context.exception(uuid: $0) }.filter { $0.series != nil }
            found = Set(models.map(\.uuid))
            stamps = try await upsert(models.map { $0.row(userID: userID) }, table: table, client: client)
            apply(stamps, to: models, context: context)
        case .events:
            let models = ids.compactMap { context.event(uuid: $0) }
            found = Set(models.map(\.uuid))
            // A never-synced event is authored by whoever pushes it; recorded before the push so the
            // row and the model agree, and outside the outbox.
            tracker.applyingRemote(in: context) {
                for event in models where event.authorID == nil { event.authorID = userID }
            }
            stamps = try await upsert(models.map { $0.row(userID: userID) }, table: table, client: client)
            apply(stamps, to: models, context: context)
        case .projects:
            let models = ids.compactMap { context.project(uuid: $0) }
            found = Set(models.map(\.uuid))
            stamps = try await upsert(models.map { $0.row(userID: userID) }, table: table, client: client)
            apply(stamps, to: models, context: context)
        case .todos:
            let models = ids.compactMap { context.todo(uuid: $0) }
            found = Set(models.map(\.uuid))
            stamps = try await upsert(models.map { $0.row(userID: userID) }, table: table, client: client)
            apply(stamps, to: models, context: context)
        }
        let stamped = Set(stamps.map(\.id))
        tracker.store.update { outbox in
            for id in ids where stamped.contains(id) || !found.contains(id) {
                // Pushed, or gone from the store before the push (the delete follows separately).
                outbox.clear(id, in: table, ifStill: .upsert)
            }
        }
    }

    private func upsert<R: SyncRow>(_ rows: [R], table: SyncTable, client: SupabaseClient) async throws -> [SyncStamp] {
        guard !rows.isEmpty else { return [] }
        return try await client
            .from(table.rawValue)
            .upsert(rows, onConflict: "id")
            .select("id, updated_at")
            .execute()
            .value
    }

    /// Records the server's `updated_at` on the pushed models so the echo of this push is skipped.
    private func apply(_ stamps: [SyncStamp], to models: [some SyncedModel], context: ModelContext) {
        let byID = Dictionary(stamps.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { first, _ in first })
        tracker.applyingRemote(in: context) {
            for model in models {
                if let stamp = byID[model.uuid] { model.syncedAt = stamp }
            }
            try? context.save()
        }
    }

    private func pushDeletes(_ table: SyncTable, ids: [UUID], client: SupabaseClient) async throws {
        try await client
            .from(table.rawValue)
            .update(["deleted_at": SupabaseCoding.timestamp(Date())])
            .in("id", values: ids.map(\.uuidString))
            .execute()
        tracker.store.update { outbox in
            for id in ids { outbox.clear(id, in: table, ifStill: .delete) }
        }
    }

    /// First sync of a sign-in: every row that has never been synced joins the outbox.
    private func enqueueNeverSynced(in context: ModelContext) throws {
        var pending: [(SyncTable, UUID)] = []
        pending += try context.fetch(FetchDescriptor<Term>()).filter { $0.syncedAt == nil }.map { (.terms, $0.uuid) }
        pending += try context.fetch(FetchDescriptor<Series>()).filter { $0.syncedAt == nil && $0.term != nil }.map { (.series, $0.uuid) }
        pending += try context.fetch(FetchDescriptor<Blackout>()).filter { $0.syncedAt == nil }.map { (.blackouts, $0.uuid) }
        pending += try context.fetch(FetchDescriptor<OccurrenceException>()).filter { $0.syncedAt == nil && $0.series != nil }.map { (.occurrenceExceptions, $0.uuid) }
        pending += try context.fetch(FetchDescriptor<Event>()).filter { $0.syncedAt == nil }.map { (.events, $0.uuid) }
        pending += try context.fetch(FetchDescriptor<Project>()).filter { $0.syncedAt == nil }.map { (.projects, $0.uuid) }
        pending += try context.fetch(FetchDescriptor<TodoItem>()).filter { $0.syncedAt == nil }.map { (.todos, $0.uuid) }
        guard !pending.isEmpty else { return }
        tracker.store.update { outbox in
            for (table, id) in pending where outbox.operation(for: id, in: table) == nil {
                outbox.markUpsert(id, in: table)
            }
        }
    }

    // MARK: Pull

    private func pullAll(client: SupabaseClient, context: ModelContext, userID: UUID) async throws {
        for table in SyncTable.pushOrder {
            switch table {
            case .terms:
                try await pull(TermRow.self, table: table, client: client, context: context, userID: userID) { row, context in
                    if let term = context.term(uuid: row.id) { term.apply(row) } else { context.insert(Term.make(from: row)) }
                } delete: { id, context in
                    if let term = context.term(uuid: id) { context.delete(term) }
                } syncedAt: { id, context in context.term(uuid: id)?.syncedAt }
            case .series:
                try await pull(SeriesRow.self, table: table, client: client, context: context, userID: userID) { row, context in
                    if let series = context.series(uuid: row.id) { series.apply(row, in: context) } else { _ = Series.make(from: row, in: context) }
                } delete: { id, context in
                    if let series = context.series(uuid: id) { context.delete(series) }
                } syncedAt: { id, context in context.series(uuid: id)?.syncedAt }
            case .blackouts:
                try await pull(BlackoutRow.self, table: table, client: client, context: context, userID: userID) { row, context in
                    if let blackout = context.blackout(uuid: row.id) { blackout.apply(row, in: context) } else { _ = Blackout.make(from: row, in: context) }
                } delete: { id, context in
                    if let blackout = context.blackout(uuid: id) { context.delete(blackout) }
                } syncedAt: { id, context in context.blackout(uuid: id)?.syncedAt }
            case .occurrenceExceptions:
                try await pull(ExceptionRow.self, table: table, client: client, context: context, userID: userID) { row, context in
                    if let exception = context.exception(uuid: row.id) { exception.apply(row, in: context) } else { _ = OccurrenceException.make(from: row, in: context) }
                } delete: { id, context in
                    if let exception = context.exception(uuid: id) { context.delete(exception) }
                } syncedAt: { id, context in context.exception(uuid: id)?.syncedAt }
            case .events:
                try await pull(EventRow.self, table: table, client: client, context: context, userID: userID) { row, context in
                    if let event = context.event(uuid: row.id) { event.apply(row) } else { context.insert(Event.make(from: row)) }
                } delete: { id, context in
                    if let event = context.event(uuid: id) { context.delete(event) }
                } syncedAt: { id, context in context.event(uuid: id)?.syncedAt }
            case .projects:
                try await pull(ProjectRow.self, table: table, client: client, context: context, userID: userID) { row, context in
                    if let project = context.project(uuid: row.id) { project.apply(row) } else { context.insert(Project.make(from: row)) }
                } delete: { id, context in
                    if let project = context.project(uuid: id) { context.delete(project) }
                } syncedAt: { id, context in context.project(uuid: id)?.syncedAt }
            case .todos:
                try await pull(TodoItemRow.self, table: table, client: client, context: context, userID: userID) { row, context in
                    if let todo = context.todo(uuid: row.id) { todo.apply(row, in: context) } else { _ = TodoItem.make(from: row, in: context) }
                } delete: { id, context in
                    if let todo = context.todo(uuid: id) { context.delete(todo) }
                } syncedAt: { id, context in context.todo(uuid: id)?.syncedAt }
            }
        }
    }

    private func pull<R: SyncRow>(
        _ type: R.Type,
        table: SyncTable,
        client: SupabaseClient,
        context: ModelContext,
        userID: UUID,
        apply: (R, ModelContext) -> Void,
        delete: (UUID, ModelContext) -> Void,
        syncedAt: (UUID, ModelContext) -> Date?
    ) async throws {
        var cursor = cursor(for: table, userID: userID)
        var start = SyncPlanner.pullStart(cursor: cursor)
        while true {
            var query = client.from(table.rawValue).select()
            if let start {
                query = query.gte("updated_at", value: SupabaseCoding.timestamp(start))
            }
            let rows: [R] = try await query
                .order("updated_at", ascending: true)
                .limit(SyncPlanner.pageSize)
                .execute()
                .value
            guard !rows.isEmpty else { break }

            let outbox = tracker.outbox
            try tracker.applyingRemote(in: context) {
                for row in rows {
                    let decision = SyncPlanner.decide(
                        pending: outbox.operation(for: row.id, in: table),
                        localSyncedAt: syncedAt(row.id, context),
                        remoteUpdatedAt: row.updatedAt,
                        remoteDeleted: row.deletedAt != nil
                    )
                    switch decision {
                    case .skip: continue
                    case .delete: delete(row.id, context)
                    case .apply: apply(row, context)
                    }
                }
                try context.save()
            }

            let newest = rows.compactMap(\.updatedAt).max()
            if let newest, newest > (cursor ?? .distantPast) {
                cursor = newest
                setCursor(newest, for: table, userID: userID)
            }
            // A short page ends the pull; a full page whose newest row is not past where we started
            // would loop forever (many rows sharing one timestamp), so it ends it too.
            guard rows.count >= SyncPlanner.pageSize, let newest, newest != start else { break }
            start = newest
        }
    }

    // MARK: Realtime

    /// One channel, one stream per table; any change just asks for a (debounced) sync, which keeps
    /// the realtime path free of its own apply logic.
    private func startRealtime() {
        guard isRealtimeEnabled, let client, realtimeChannel == nil else { return }
        let channel = client.realtimeV2.channel("timecontrol-sync")
        realtimeChannel = channel
        let tables = ["events", "groups", "group_members", "terms", "series", "blackouts", "occurrence_exceptions", "projects", "todos"]
        let streams = tables.map { channel.postgresChange(AnyAction.self, schema: "public", table: $0) }
        realtimeTasks = streams.map { stream in
            Task { [weak self] in
                for await _ in stream {
                    self?.scheduleSync()
                }
            }
        }
        realtimeTasks.append(Task {
            do {
                try await channel.subscribe()
            } catch {
                print("SyncService: realtime subscribe failed: \(error)")
            }
        })
    }

    private func stopRealtime() {
        for task in realtimeTasks { task.cancel() }
        realtimeTasks = []
        if let channel = realtimeChannel {
            realtimeChannel = nil
            Task { await channel.unsubscribe() }
        }
    }

    // MARK: Account changes

    /// Signing out leaves the user's own data in place and drops what belonged to the groups: the
    /// group rows and other members' events.
    private func purgeSharedData(exceptAuthor author: UUID?) {
        guard let container else { return }
        let context = container.mainContext
        tracker.applyingRemote(in: context) {
            let groups = (try? context.fetch(FetchDescriptor<SharedGroup>())) ?? []
            for group in groups { context.delete(group) }
            let events = (try? context.fetch(FetchDescriptor<Event>())) ?? []
            for event in events where event.groupID != nil && event.authorID != nil && event.authorID != author {
                context.delete(event)
            }
            try? context.save()
        }
    }

    /// A different account than the last one signed in: forget what was synced so everything local
    /// uploads into the new account on reconcile.
    private func resetSyncedAt() {
        guard let container else { return }
        let context = container.mainContext
        tracker.applyingRemote(in: context) {
            for term in (try? context.fetch(FetchDescriptor<Term>())) ?? [] { term.syncedAt = nil }
            for series in (try? context.fetch(FetchDescriptor<Series>())) ?? [] { series.syncedAt = nil }
            for blackout in (try? context.fetch(FetchDescriptor<Blackout>())) ?? [] { blackout.syncedAt = nil }
            for exception in (try? context.fetch(FetchDescriptor<OccurrenceException>())) ?? [] { exception.syncedAt = nil }
            for event in (try? context.fetch(FetchDescriptor<Event>())) ?? [] { event.syncedAt = nil }
            for project in (try? context.fetch(FetchDescriptor<Project>())) ?? [] { project.syncedAt = nil }
            for todo in (try? context.fetch(FetchDescriptor<TodoItem>())) ?? [] { todo.syncedAt = nil }
            try? context.save()
        }
        if let last = lastUserID {
            for table in SyncTable.allCases { setCursor(nil, for: table, userID: last) }
        }
    }

    // MARK: Cursors

    private var lastUserKey: String { "sync\(instanceKey).lastUserID" }

    private var lastUserID: UUID? {
        get { (UserDefaults.standard.string(forKey: lastUserKey)).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: lastUserKey) }
    }

    private func cursorKey(_ table: SyncTable, userID: UUID) -> String {
        "sync\(instanceKey).cursor.\(userID.uuidString).\(table.rawValue)"
    }

    private func cursor(for table: SyncTable, userID: UUID) -> Date? {
        let seconds = UserDefaults.standard.double(forKey: cursorKey(table, userID: userID))
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }

    private func setCursor(_ date: Date?, for table: SyncTable, userID: UUID) {
        UserDefaults.standard.set(date?.timeIntervalSince1970 ?? 0, forKey: cursorKey(table, userID: userID))
    }

    private static func describe(_ error: any Error) -> String {
        if let postgrest = error as? PostgrestError { return postgrest.message }
        return error.localizedDescription
    }
}

/// `id, updated_at` as returned from an upsert.
nonisolated struct SyncStamp: Decodable, Sendable {
    var id: UUID
    var updatedAt: Date
}

/// The models the sync service stamps after a push.
@MainActor
protocol SyncedModel: AnyObject {
    var uuid: UUID { get }
    var syncedAt: Date? { get set }
}

extension Term: SyncedModel {}
extension Series: SyncedModel {}
extension Blackout: SyncedModel {}
extension OccurrenceException: SyncedModel {}
extension Event: SyncedModel {}
extension Project: SyncedModel {}
extension TodoItem: SyncedModel {}
