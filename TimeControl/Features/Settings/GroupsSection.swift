import SwiftData
import SwiftUI

/// The "Groups" section of Settings: the groups this account belongs to, and the two ways into a new
/// one. Groups need an account, so signed out this is a single line pointing at the section above.
struct GroupsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SharedGroup.name) private var groups: [SharedGroup]

    @State private var showingNewGroup = false
    @State private var showingJoin = false

    private var auth: AuthService { .shared }
    private var service: GroupService { .shared }

    private var isAtCap: Bool { groups.count >= SharedGroup.maxPerAccount }

    var body: some View {
        Section {
            if auth.isSignedIn {
                ForEach(groups) { group in
                    NavigationLink {
                        GroupDetailView(group: group)
                    } label: {
                        row(group)
                    }
                }
                Button("New Group…") { showingNewGroup = true }
                    .disabled(isAtCap)
                Button("Join with Code…") { showingJoin = true }
                    .disabled(isAtCap)
            } else {
                Text("Sign in to create or join groups.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Groups")
        } footer: {
            if auth.isSignedIn {
                Text(footerText)
            }
        }
        .task(id: auth.userID) {
            guard auth.isSignedIn else { return }
            await service.refresh(into: modelContext)
        }
        .sheet(isPresented: $showingNewGroup) { GroupEditorSheet() }
        .sheet(isPresented: $showingJoin) { JoinGroupSheet() }
    }

    private var footerText: String {
        if let error = service.lastError {
            return error.errorDescription ?? String(describing: error)
        }
        if isAtCap {
            return "\(groups.count) of \(SharedGroup.maxPerAccount) groups. Leave one to make room for another."
        }
        return "\(groups.count) of \(SharedGroup.maxPerAccount) groups."
    }

    private func row(_ group: SharedGroup) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: group.effectiveColorHex))
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                Text(subtitle(group))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func subtitle(_ group: SharedGroup) -> String {
        let members = group.memberCount == 1 ? "1 member" : "\(group.memberCount) members"
        return "\(members) · \(group.isOwner ? "Owner" : "Member")"
    }
}
