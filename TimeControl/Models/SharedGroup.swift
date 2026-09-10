import Foundation
import SwiftData
import TimeControlCore

/// One member of a group as the roster shows them. Stored inline on ``SharedGroup``; the server's
/// `group_members` joined with `profiles` is the source.
nonisolated struct GroupMember: Codable, Hashable, Sendable, Identifiable {
    var userID: UUID
    var displayName: String
    var role: String
    var joinedAt: Date

    var id: UUID { userID }
    var isOwner: Bool { role == "owner" }
}

extension SchemaV2 {
    /// A shared group the signed-in user belongs to: a local cache of the server's `groups` row plus
    /// this user's own `group_members` row. Never created locally; `GroupService` pulls it.
    @Model
    final class SharedGroup {
        /// The server's group id.
        var uuid: UUID = UUID()
        var name: String = ""
        /// The group's colour as its creator set it; what every member sees unless they override it.
        var colorHex: String = "#4F7CFF"
        /// This member's own colour for the group on their calendar; nil follows `colorHex`.
        var colorOverrideHex: String?
        var joinCode: String = ""
        var createdBy: UUID = UUID()
        /// `owner` or `member`.
        var role: String = "member"
        var members: [GroupMember] = []
        var createdAt: Date = Date()
        /// The server's `updated_at` for the state last pulled.
        var syncedAt: Date?

        init(uuid: UUID, name: String, colorHex: String, joinCode: String, createdBy: UUID, role: String) {
            self.uuid = uuid
            self.name = name
            self.colorHex = colorHex
            self.joinCode = joinCode
            self.createdBy = createdBy
            self.role = role
        }
    }
}

extension SharedGroup {
    /// What this member's calendar paints the group's events with.
    var effectiveColorHex: String { colorOverrideHex ?? colorHex }

    var isOwner: Bool { role == "owner" }

    var memberCount: Int { members.count }

    /// Owner first, then by name.
    var sortedMembers: [GroupMember] {
        members.sorted { a, b in
            if a.isOwner != b.isOwner { return a.isOwner }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    func displayName(of userID: UUID) -> String? {
        members.first { $0.userID == userID }?.displayName
    }

    /// Five groups per account, matching the server's trigger.
    static let maxPerAccount = 5
}
