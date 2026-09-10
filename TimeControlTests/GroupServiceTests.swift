import Foundation
import SwiftData
import Testing
import TimeControlCore
@testable import TimeControl

@Suite struct GroupServiceTests {
    private struct Store {
        let container: ModelContainer
        var context: ModelContext { container.mainContext }
        init() throws { container = try ModelContainerFactory.make(inMemory: true) }
    }

    private let me = UUID()
    private let friend = UUID()

    private func service() -> GroupService {
        let url = URL.temporaryDirectory.appending(path: "groups-\(UUID().uuidString).json")
        return GroupService(client: nil, auth: AuthService(client: nil), tracker: SyncTracker(store: SyncOutboxStore(url: url)))
    }

    private func group(_ id: UUID, name: String, deleted: Bool = false) -> GroupRow {
        GroupRow(id: id, name: name, colorHex: "#10B981", joinCode: "ABCD2345", createdBy: friend, createdAt: Date(), updatedAt: Date(), deletedAt: deleted ? Date() : nil)
    }

    private func member(_ groupID: UUID, _ userID: UUID, role: String = "member", name: String, override: String? = nil) -> GroupMemberRow {
        GroupMemberRow(groupId: groupID, userId: userID, role: role, colorOverrideHex: override, joinedAt: Date(), updatedAt: Date(), profiles: .init(displayName: name))
    }

    @Test func appliesRosterRoleAndOverride() throws {
        let store = try Store()
        let id = UUID()
        try service().apply(
            groups: [group(id, name: "Study")],
            members: [member(id, friend, role: "owner", name: "Sam"), member(id, me, name: "Me", override: "#F59E0B")],
            userID: me,
            into: store.context
        )
        let saved = try #require(store.context.group(uuid: id))
        #expect(saved.name == "Study")
        #expect(saved.role == "member")
        #expect(saved.colorOverrideHex == "#F59E0B")
        #expect(saved.effectiveColorHex == "#F59E0B")
        #expect(saved.sortedMembers.map(\.displayName) == ["Sam", "Me"])
        #expect(saved.displayName(of: friend) == "Sam")
    }

    @Test func dropsGroupsThisUserIsNotInAndDeletedOnes() throws {
        let store = try Store()
        let mine = UUID(), theirs = UUID(), gone = UUID()
        let svc = service()
        try svc.apply(groups: [group(mine, name: "Mine")], members: [member(mine, me, name: "Me")], userID: me, into: store.context)
        #expect(store.context.group(uuid: mine) != nil)
        try svc.apply(
            groups: [group(theirs, name: "Theirs"), group(gone, name: "Gone", deleted: true)],
            members: [member(theirs, friend, name: "Sam"), member(gone, me, name: "Me")],
            userID: me,
            into: store.context
        )
        #expect(store.context.group(uuid: mine) == nil, "left elsewhere")
        #expect(store.context.group(uuid: theirs) == nil, "not a member")
        #expect(store.context.group(uuid: gone) == nil, "deleted by its owner")
    }

    @Test func leavingAGroupDropsOtherMembersEventsButKeepsMine() throws {
        let store = try Store()
        let id = UUID()
        let svc = service()
        try svc.apply(groups: [group(id, name: "Study")], members: [member(id, me, name: "Me")], userID: me, into: store.context)
        let now = Date()
        let theirs = Event(title: "Theirs", kind: .other, start: now, end: now, groupID: id)
        theirs.authorID = friend
        let mine = Event(title: "Mine", kind: .other, start: now, end: now, groupID: id)
        mine.authorID = me
        store.context.insert(theirs)
        store.context.insert(mine)
        try store.context.save()

        try svc.apply(groups: [], members: [], userID: me, into: store.context)
        #expect(store.context.event(uuid: theirs.uuid) == nil)
        #expect(store.context.event(uuid: mine.uuid) != nil)
    }

    @Test func rpcErrorsMapToCases() {
        struct Fake: Error, CustomStringConvertible { let description: String }
        #expect(GroupService.GroupError.wrap(Fake(description: "PostgrestError(message: group_limit_reached)")) == .limitReached)
        #expect(GroupService.GroupError.wrap(Fake(description: "invalid_join_code")) == .invalidCode)
        #expect(GroupService.GroupError.wrap(Fake(description: "only_owner_can_delete_group")) == .ownerOnly)
    }
}
