import Foundation
import Observation
import Supabase
import SwiftData
import TimeControlCore

/// Groups the signed-in user belongs to: pulled from the server into `SharedGroup` rows, created and
/// joined through the RPCs, left by deleting the member row. Group *events* are ordinary events with a
/// `groupID`, handled by `SyncService`.
@MainActor
@Observable
final class GroupService {
    static let shared = GroupService()

    enum GroupError: Error, LocalizedError, Equatable {
        case unavailable
        case notSignedIn
        case limitReached
        case invalidCode
        case ownerOnly
        case nameRequired
        case server(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: "This build has no account service configured."
            case .notSignedIn: "Sign in to use groups."
            case .limitReached: "You can be in at most \(SharedGroup.maxPerAccount) groups."
            case .invalidCode: "That join code does not match a group."
            case .ownerOnly: "Only the group's creator can delete it."
            case .nameRequired: "Give the group a name."
            case .server(let message): message
            }
        }

        /// Maps the RPCs' `raise exception` messages onto cases.
        static func wrap(_ error: any Error) -> GroupError {
            if let already = error as? GroupError { return already }
            let text = String(describing: error)
            if text.contains("group_limit_reached") { return .limitReached }
            if text.contains("invalid_join_code") { return .invalidCode }
            if text.contains("only_owner_can_delete_group") { return .ownerOnly }
            if text.contains("group_name_required") { return .nameRequired }
            if text.contains("not_authenticated") { return .notSignedIn }
            if let postgrest = error as? PostgrestError { return .server(postgrest.message) }
            return .server(error.localizedDescription)
        }
    }

    private(set) var isRefreshing = false
    private(set) var lastError: GroupError?

    private let client: SupabaseClient?
    private let auth: AuthService
    private let tracker: SyncTracker

    init(client: SupabaseClient? = SupabaseClientProvider.shared, auth: AuthService = .shared, tracker: SyncTracker = .shared) {
        self.client = client
        self.auth = auth
        self.tracker = tracker
    }

    // MARK: Pull

    /// Brings the local `SharedGroup` rows in line with the server: groups joined elsewhere appear,
    /// groups left or deleted go, and events of a group this user is no longer in are dropped.
    func refresh(into context: ModelContext) async {
        guard let client, let userID = auth.userID else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let groups: [GroupRow] = try await client.from("groups").select().execute().value
            let members: [GroupMemberRow] = try await client
                .from("group_members")
                .select("*, profiles(display_name)")
                .execute()
                .value
            try apply(groups: groups, members: members, userID: userID, into: context)
            lastError = nil
        } catch {
            lastError = GroupError.wrap(error)
            print("GroupService: refresh failed: \(error)")
        }
    }

    /// Pure enough to test with an in-memory store: writes the server's picture of the groups.
    func apply(groups: [GroupRow], members: [GroupMemberRow], userID: UUID, into context: ModelContext) throws {
        let membersByGroup = Dictionary(grouping: members, by: \.groupId)
        let live = groups.filter { $0.deletedAt == nil && membersByGroup[$0.id]?.contains { $0.userId == userID } == true }
        let liveIDs = Set(live.map(\.id))

        let existing = try context.fetch(FetchDescriptor<SharedGroup>())
        var byID = Dictionary(existing.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })

        try tracker.applyingRemote(in: context) {
            for row in live {
                let roster = (membersByGroup[row.id] ?? []).map { member in
                    GroupMember(
                        userID: member.userId,
                        displayName: member.profiles?.displayName ?? "Member",
                        role: member.role,
                        joinedAt: member.joinedAt ?? Date()
                    )
                }
                let mine = membersByGroup[row.id]?.first { $0.userId == userID }
                let group = byID[row.id] ?? {
                    let created = SharedGroup(uuid: row.id, name: row.name, colorHex: row.colorHex, joinCode: row.joinCode, createdBy: row.createdBy, role: mine?.role ?? "member")
                    context.insert(created)
                    byID[row.id] = created
                    return created
                }()
                group.name = row.name
                group.colorHex = row.colorHex
                group.joinCode = row.joinCode
                group.createdBy = row.createdBy
                group.role = mine?.role ?? "member"
                group.colorOverrideHex = mine?.colorOverrideHex
                group.members = roster
                group.syncedAt = row.updatedAt
                if let created = row.createdAt { group.createdAt = created }
            }

            for group in existing where !liveIDs.contains(group.uuid) {
                // Other members' events in a group this user is no longer in are theirs, not ours.
                let gone = group.uuid
                let orphaned = try context.fetch(FetchDescriptor<Event>(predicate: #Predicate { $0.groupID == gone }))
                for event in orphaned where event.authorID != userID {
                    context.delete(event)
                }
                context.delete(group)
            }
            try context.save()
        }
    }

    // MARK: Actions

    @discardableResult
    func create(name: String, colorHex: String, into context: ModelContext) async throws -> SharedGroup {
        guard let client else { throw GroupError.unavailable }
        guard auth.isSignedIn else { throw GroupError.notSignedIn }
        guard auth.userID != nil else { throw GroupError.notSignedIn }
        do {
            let row: GroupRow = try await client
                .rpc("create_group", params: ["p_name": name, "p_color_hex": colorHex])
                .execute()
                .value
            await refresh(into: context)
            guard let group = context.group(uuid: row.id) else { throw GroupError.server("The group was created but could not be loaded.") }
            return group
        } catch {
            throw GroupError.wrap(error)
        }
    }

    @discardableResult
    func join(code: String, into context: ModelContext) async throws -> SharedGroup {
        guard let client else { throw GroupError.unavailable }
        guard auth.isSignedIn else { throw GroupError.notSignedIn }
        do {
            let row: GroupRow = try await client
                .rpc("join_group", params: ["p_code": code])
                .execute()
                .value
            await refresh(into: context)
            guard let group = context.group(uuid: row.id) else { throw GroupError.server("Joined, but the group could not be loaded.") }
            return group
        } catch {
            throw GroupError.wrap(error)
        }
    }

    func leave(_ group: SharedGroup, in context: ModelContext) async throws {
        guard let client else { throw GroupError.unavailable }
        do {
            try await client.rpc("leave_group", params: ["p_group_id": group.uuid.uuidString]).execute()
            await refresh(into: context)
        } catch {
            throw GroupError.wrap(error)
        }
    }

    /// Creator only; the server refuses anyone else.
    func delete(_ group: SharedGroup, in context: ModelContext) async throws {
        guard let client else { throw GroupError.unavailable }
        do {
            try await client
                .from("groups")
                .update(["deleted_at": SupabaseCoding.timestamp(Date())])
                .eq("id", value: group.uuid.uuidString)
                .execute()
            await refresh(into: context)
        } catch {
            throw GroupError.wrap(error)
        }
    }

    /// Any member may rename or recolour the group for everyone.
    func update(_ group: SharedGroup, name: String, colorHex: String, in context: ModelContext) async throws {
        guard let client else { throw GroupError.unavailable }
        do {
            try await client
                .from("groups")
                .update(["name": name, "color_hex": colorHex])
                .eq("id", value: group.uuid.uuidString)
                .execute()
            group.name = name
            group.colorHex = colorHex
            await refresh(into: context)
        } catch {
            throw GroupError.wrap(error)
        }
    }

    /// This member's own colour for the group; nil follows the group's colour.
    func setColorOverride(_ hex: String?, for group: SharedGroup, in context: ModelContext) async throws {
        guard let client else { throw GroupError.unavailable }
        guard let userID = auth.userID else { throw GroupError.notSignedIn }
        do {
            try await client
                .from("group_members")
                .update(["color_override_hex": hex])
                .eq("group_id", value: group.uuid.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
            group.colorOverrideHex = hex
        } catch {
            throw GroupError.wrap(error)
        }
    }
}
