import SwiftUI

/// The "Account" section of Settings: who is signed in, the profile name other members see, what sync
/// is doing, and the way back out.
struct AccountSection: View {
    @State private var showingSignIn = false
    @State private var draftName = ""
    @State private var isSavingName = false
    @State private var confirmSignOut = false
    @State private var errorMessage: String?
    @FocusState private var nameFieldFocused: Bool

    private var auth: AuthService { .shared }
    private var sync: SyncService { .shared }

    var body: some View {
        Section {
            switch auth.state {
            case .unavailable:
                Text("This build carries no account service, so TimeControl keeps everything on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .signedOut:
                Text("Sign in to sync across devices and share events with groups.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Sign In…") { showingSignIn = true }
            case .signedIn(_, let email):
                LabeledContent("Email", value: email ?? "—")
                nameRow
                syncRow
                Button("Sign Out…", role: .destructive) { confirmSignOut = true }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Account")
        }
        .task(id: auth.userID) {
            guard auth.isSignedIn else { return }
            await auth.loadProfile()
            draftName = auth.displayName
        }
        .sheet(isPresented: $showingSignIn) { SignInSheet() }
        .confirmationDialog(
            "Sign out of TimeControl?",
            isPresented: $confirmSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) { signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your terms, events and todos stay on this device. Sign back in to sync them again.")
        }
    }

    private var nameRow: some View {
        HStack {
            TextField("Display name", text: $draftName, prompt: Text("Name other members see"))
                .focused($nameFieldFocused)
                .onSubmit { saveName() }
                .onChange(of: nameFieldFocused) { _, focused in
                    if !focused { saveName() }
                }
            if isSavingName {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var syncRow: some View {
        HStack {
            Button("Sync Now") { syncNow() }
                .disabled(sync.status == .syncing || !sync.isAvailable)
            if sync.status == .syncing {
                ProgressView()
                    .controlSize(.small)
            }
            Spacer()
            Text(syncCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// "Idle · 2 minutes ago · 3 waiting", trimmed to whichever parts there are.
    private var syncCaption: String {
        var parts = [statusText]
        if let lastSyncDate = sync.lastSyncDate {
            parts.append(lastSyncDate.formatted(.relative(presentation: .named)))
        }
        if sync.pendingCount > 0 {
            parts.append("\(sync.pendingCount) waiting")
        }
        return parts.joined(separator: " · ")
    }

    private var statusText: String {
        switch sync.status {
        case .off: "Local only"
        case .idle: "Idle"
        case .syncing: "Syncing…"
        case .failed(let message): "Failed: \(message)"
        }
    }

    private func saveName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != auth.displayName, !isSavingName else { return }
        Task {
            isSavingName = true
            defer { isSavingName = false }
            do {
                try await auth.updateDisplayName(trimmed)
                draftName = auth.displayName
                errorMessage = nil
            } catch {
                errorMessage = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
            }
        }
    }

    private func syncNow() {
        Task { await sync.syncNow() }
    }

    private func signOut() {
        Task {
            await auth.signOut()
            draftName = ""
            errorMessage = nil
        }
    }
}
