import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// One group: how to invite people into it, this member's own colour for it, who else is in it, and
/// the ways out. Pushed from the "Groups" section of Settings.
struct GroupDetailView: View {
    let group: SharedGroup

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var colorOverride: String?
    @State private var showingEdit = false
    @State private var confirmLeave = false
    @State private var confirmDelete = false
    @State private var didCopyCode = false
    @State private var isBusy = false
    @State private var errorMessage: String?

    init(group: SharedGroup) {
        self.group = group
        _colorOverride = State(initialValue: group.colorOverrideHex)
    }

    private var auth: AuthService { .shared }

    private var shareText: String { "Join my TimeControl group with code \(group.joinCode)" }

    var body: some View {
        // Leaving or deleting takes this group's row away before the pop lands, and SwiftData traps on
        // a deleted model: show nothing for those few frames rather than read one.
        if group.isDeleted {
            Color.clear
        } else {
            content
        }
    }

    private var content: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hex: group.effectiveColorHex))
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name)
                            .font(.headline)
                        Text(group.isOwner ? "You created this group" : "Shared with you")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            joinCodeSection
            colorSection
            membersSection
            actionsSection

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(group.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showingEdit) { GroupEditorSheet(group: group) }
        .confirmationDialog("Leave “\(group.name)”?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave Group", role: .destructive) { leave() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its events disappear from your calendar. You can rejoin with the code.")
        }
        .confirmationDialog("Delete “\(group.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Group", role: .destructive) { deleteGroup() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every member loses the group and its events. This cannot be undone.")
        }
    }

    private var joinCodeSection: some View {
        Section {
            HStack {
                Text(group.joinCode)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                Spacer()
                Button(didCopyCode ? "Copied" : "Copy") { copyJoinCode() }
                ShareLink(item: shareText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("Join code")
        } footer: {
            Text("Anyone with this code can join the group and see its events.")
        }
    }

    private var colorSection: some View {
        Section {
            ColorSwatchRow(
                selection: $colorOverride,
                matching: nil,
                inherited: (hex: group.colorHex, symbol: "person.2.fill", label: "Match the group")
            )
            .onChange(of: colorOverride) { _, newValue in
                setColorOverride(newValue)
            }
        } header: {
            Text("My colour")
        } footer: {
            Text("Only you see this. Leave it on the group's own colour to follow whatever the group picks.")
        }
    }

    private var membersSection: some View {
        Section("Members") {
            ForEach(group.sortedMembers) { member in
                HStack {
                    Text(member.displayName)
                    if member.userID == auth.userID {
                        Text("You")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(member.isOwner ? "Owner" : "Member")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button("Edit Group…") { showingEdit = true }
                .disabled(isBusy)
            if group.isOwner {
                Button("Delete Group…", role: .destructive) { confirmDelete = true }
                    .disabled(isBusy)
            } else {
                Button("Leave Group…", role: .destructive) { confirmLeave = true }
                    .disabled(isBusy)
            }
        } footer: {
            if group.isOwner {
                Text("The group's creator cannot leave it — delete it instead.")
            }
        }
    }

    private func copyJoinCode() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(group.joinCode, forType: .string)
        #else
        UIPasteboard.general.string = group.joinCode
        #endif
        didCopyCode = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopyCode = false
        }
    }

    private func setColorOverride(_ hex: String?) {
        guard hex != group.colorOverrideHex else { return }
        Task {
            do {
                try await GroupService.shared.setColorOverride(hex, for: group, in: modelContext)
                errorMessage = nil
            } catch {
                colorOverride = group.colorOverrideHex
                errorMessage = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
            }
        }
    }

    private func leave() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await GroupService.shared.leave(group, in: modelContext)
                dismiss()
            } catch {
                errorMessage = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
            }
        }
    }

    private func deleteGroup() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await GroupService.shared.delete(group, in: modelContext)
                dismiss()
            } catch {
                errorMessage = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
            }
        }
    }
}
