import Foundation
import Supabase
import SwiftData
import Testing
import TimeControlCore
@testable import TimeControl

/// End to end against the real hosted project, with throwaway users that are deleted afterwards.
/// Off unless the service-role key is in the environment; `xcodebuild` passes `TEST_RUNNER_`-prefixed
/// variables through to the test host:
///
///     TEST_RUNNER_SUPABASE_SERVICE_ROLE_KEY=… xcodebuild … test -only-testing:TimeControlTests/SyncIntegrationTests
///
/// The project URL and publishable key come from the app's Info.plist (the build's xcconfig) unless
/// `TEST_RUNNER_SUPABASE_URL` / `TEST_RUNNER_SUPABASE_PUBLISHABLE_KEY` override them.
@Suite(.serialized) struct SyncIntegrationTests {
    nonisolated static let environment = ProcessInfo.processInfo.environment
    nonisolated static var serviceKey: String? { environment["SUPABASE_SERVICE_ROLE_KEY"] }
    static var url: URL? { environment["SUPABASE_URL"].flatMap { URL(string: $0) } ?? SupabaseConfig.url }
    static var anonKey: String? { environment["SUPABASE_PUBLISHABLE_KEY"] ?? SupabaseConfig.apiKey }
    nonisolated static var isConfigured: Bool { serviceKey != nil }

    // MARK: Fixtures

    /// The SDK's default session store is the keychain, shared by every client in the process; each
    /// device here keeps its own session in memory instead.
    nonisolated final class MemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
        private var values: [String: Data] = [:]
        private let lock = NSLock()

        func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
        func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
        func remove(key: String) throws { lock.withLock { values[key] = nil } }
    }

    /// One signed-in app instance with its own store.
    final class Device {
        let container: ModelContainer
        let client: SupabaseClient
        let auth: AuthService
        let tracker: SyncTracker
        let groups: GroupService
        let sync: SyncService

        var context: ModelContext { container.mainContext }

        init(url: URL, key: String, name: String) throws {
            container = try ModelContainerFactory.make(inMemory: true)
            client = SupabaseClient(
                supabaseURL: url,
                supabaseKey: key,
                options: SupabaseClientOptions(
                    db: .init(encoder: SupabaseCoding.encoder, decoder: SupabaseCoding.decoder),
                    auth: .init(storage: MemoryAuthStorage())
                )
            )
            auth = AuthService(client: client)
            let outbox = URL.temporaryDirectory.appending(path: "outbox-\(name)-\(UUID().uuidString).json")
            tracker = SyncTracker(store: SyncOutboxStore(url: outbox))
            groups = GroupService(client: client, auth: auth, tracker: tracker)
            sync = SyncService(client: client, auth: auth, tracker: tracker, groups: groups, instanceKey: ".\(name)-\(UUID().uuidString)")
            sync.isRealtimeEnabled = false
        }

        /// Signs in and completes the first sync (the reconcile that uploads local rows and the pull).
        func signIn(email: String, password: String) async throws {
            try await client.auth.signIn(email: email, password: password)
            sync.start(container: container)
            await sync.syncNow()
        }

        func save() throws { try context.save() }
    }

    /// The GoTrue admin API, for creating and deleting the throwaway users.
    struct Admin {
        let url: URL
        let key: String

        struct User: Decodable {
            let id: UUID
            let email: String?
        }

        struct AdminError: Error, CustomStringConvertible {
            let description: String
        }

        func createUser(email: String, password: String) async throws -> User {
            var request = URLRequest(url: url.appending(path: "auth/v1/admin/users"))
            request.httpMethod = "POST"
            request.setValue(key, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password, "email_confirm": true])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw AdminError(description: "createUser: \(String(decoding: data, as: UTF8.self))")
            }
            return try JSONDecoder().decode(User.self, from: data)
        }

        func deleteUser(id: UUID) async throws {
            var request = URLRequest(url: url.appending(path: "auth/v1/admin/users/\(id.uuidString.lowercased())"))
            request.httpMethod = "DELETE"
            request.setValue(key, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw AdminError(description: "deleteUser: \(String(decoding: data, as: UTF8.self))")
            }
        }
    }

    // MARK: The test

    @Test(.enabled(if: SyncIntegrationTests.isConfigured))
    func groupEventsFlowBetweenMembersAndPersonalDataBetweenDevices() async throws {
        let url = try #require(Self.url)
        let anon = try #require(Self.anonKey)
        let service = try #require(Self.serviceKey)
        let admin = Admin(url: url, key: service)
        let stamp = Int(Date().timeIntervalSince1970)
        let password = "Throwaway-\(stamp)-pw"
        let a = try await admin.createUser(email: "tc-sync-a-\(stamp)@example.com", password: password)
        let b = try await admin.createUser(email: "tc-sync-b-\(stamp)@example.com", password: password)

        var failure: (any Error)?
        do {
            try await run(url: url, anon: anon, a: a, b: b, password: password)
        } catch {
            failure = error
        }
        try? await admin.deleteUser(id: a.id)
        try? await admin.deleteUser(id: b.id)
        if let failure { throw failure }
    }

    private func run(url: URL, anon: String, a: Admin.User, b: Admin.User, password: String) async throws {
        let now = Date()
        let devA = try Device(url: url, key: anon, name: "A")
        try await devA.signIn(email: try #require(a.email), password: password)
        let devB = try Device(url: url, key: anon, name: "B")
        try await devB.signIn(email: try #require(b.email), password: password)
        #expect(devA.auth.userID == a.id)

        // Personal data: A's term, course, project, todo and event reach a second device of A's,
        // relationships intact.
        let term = Term(name: "Fall 2026", start: DayKey(year: 2026, month: 9, day: 7), end: DayKey(year: 2026, month: 12, day: 18))
        devA.context.insert(term)
        let course = Series(title: "CS201", weekdays: [.monday], startMinute: 600, endMinute: 660, endWeek: 14)
        devA.context.insert(course)
        course.term = term
        let project = Project(title: "Thesis")
        devA.context.insert(project)
        let todo = TodoItem(title: "Outline", day: .today(), project: project)
        devA.context.insert(todo)
        let personal = Event(title: "Dentist", kind: .appointment, start: now, end: now.addingTimeInterval(3600))
        devA.context.insert(personal)
        try devA.save()
        await devA.sync.syncNow()
        #expect(devA.sync.status == .idle)
        #expect(devA.tracker.outbox.isEmpty)
        #expect(term.syncedAt != nil)
        #expect(personal.authorID == a.id)

        let devA2 = try Device(url: url, key: anon, name: "A2")
        try await devA2.signIn(email: try #require(a.email), password: password)
        let term2 = try #require(devA2.context.term(uuid: term.uuid))
        #expect(term2.name == "Fall 2026")
        #expect(devA2.context.series(uuid: course.uuid)?.term?.uuid == term.uuid)
        #expect(devA2.context.todo(uuid: todo.uuid)?.project?.uuid == project.uuid)
        #expect(devA2.context.event(uuid: personal.uuid)?.title == "Dentist")

        // Groups: A creates, B joins by code.
        let group = try await devA.groups.create(name: "Study", colorHex: "#10B981", into: devA.context)
        #expect(group.isOwner)
        #expect(group.joinCode.count == 8)
        let joined = try await devB.groups.join(code: group.joinCode.lowercased(), into: devB.context)
        #expect(joined.uuid == group.uuid)
        #expect(!joined.isOwner)
        #expect(joined.memberCount == 2)

        // A's group event appears on B in the group's colour, with A as its author.
        let shared = Event(title: "Study session", kind: .other, start: now, end: now.addingTimeInterval(7200), groupID: group.uuid)
        devA.context.insert(shared)
        try devA.save()
        await devA.sync.syncNow()
        await devB.sync.syncNow()
        let onB = try #require(devB.context.event(uuid: shared.uuid))
        #expect(onB.groupID == group.uuid)
        #expect(onB.authorID == a.id)
        let snapshotB = ScheduleSnapshot.load(from: devB.context)
        #expect(snapshotB.occurrences(on: DayKey(now)).first { $0.eventID == shared.uuid }?.colorHex == "#10B981")

        // Any member edits: B renames it, A sees the change, and the author stays A.
        onB.title = "Study session (moved)"
        try devB.save()
        await devB.sync.syncNow()
        #expect(devB.sync.status == .idle)
        await devA.sync.syncNow()
        #expect(shared.title == "Study session (moved)")
        #expect(shared.authorID == a.id)

        // B's personal events never reach A.
        let bPrivate = Event(title: "B private", kind: .personal, start: now, end: now.addingTimeInterval(600))
        devB.context.insert(bPrivate)
        try devB.save()
        await devB.sync.syncNow()
        await devA.sync.syncNow()
        #expect(devA.context.event(uuid: bPrivate.uuid) == nil)

        // A deletes the group event: the tombstone reaches B.
        devA.context.delete(shared)
        try devA.save()
        await devA.sync.syncNow()
        await devB.sync.syncNow()
        #expect(devB.context.event(uuid: shared.uuid) == nil)

        // A's other device deletes the term: the server cascades to the course, and A sees both go.
        devA2.context.delete(term2)
        try devA2.save()
        await devA2.sync.syncNow()
        await devA.sync.syncNow()
        #expect(devA.context.term(uuid: term.uuid) == nil)
        #expect(devA.context.series(uuid: course.uuid) == nil)

        // B leaves: the group is gone on B, and A's roster shrinks.
        try await devB.groups.leave(joined, in: devB.context)
        #expect(devB.context.group(uuid: group.uuid) == nil)
        await devA.groups.refresh(into: devA.context)
        #expect(devA.context.group(uuid: group.uuid)?.memberCount == 1)

        // Five groups per account, enforced by the server.
        for index in 0..<5 {
            _ = try await devB.groups.create(name: "Group \(index)", colorHex: "#4F7CFF", into: devB.context)
        }
        await #expect(throws: GroupService.GroupError.limitReached) {
            _ = try await devB.groups.create(name: "One too many", colorHex: "#4F7CFF", into: devB.context)
        }
        await #expect(throws: GroupService.GroupError.invalidCode) {
            _ = try await devA.groups.join(code: "NOPE0000", into: devA.context)
        }
    }
}
