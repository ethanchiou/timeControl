import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    #if os(iOS)
    /// Settings is a sheet on iOS (it is not a tab), so it needs its own way out.
    @Environment(\.dismiss) private var dismiss
    #endif

    @State private var rolloverEnabled = RolloverService.isEnabled
    #if DEBUG
    @State private var sampleDataLoaded = false
    @State private var confirmDeleteAllData = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                AccountSection()
                GroupsSection()
                NotificationSettingsSection()
                CalendarMirrorSection()
                BackupSection()
                #if DEBUG
                developerSection
                #endif
                aboutSection
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
            #if DEBUG
            .onAppear { sampleDataLoaded = SampleData.isLoaded(in: modelContext) }
            #endif
        }
    }

    @ViewBuilder
    private var generalSection: some View {
        Section("General") {
            Toggle("Roll unfinished todos over to today", isOn: $rolloverEnabled)
                .onChange(of: rolloverEnabled) { _, newValue in
                    RolloverService.isEnabled = newValue
                }
            Button {
                showCommandPalette()
            } label: {
                HStack {
                    Label("Quick Add…", systemImage: "command")
                    #if os(macOS)
                    Spacer()
                    Text("⌘K")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    #endif
                }
            }
        }
    }

    /// iOS presents Settings as a sheet, and a second sheet cannot go up over it: close this one first.
    private func showCommandPalette() {
        #if os(iOS)
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            appState.isCommandPaletteShown = true
        }
        #else
        appState.isCommandPaletteShown = true
        #endif
    }

    #if DEBUG
    @ViewBuilder
    private var developerSection: some View {
        Section("Developer") {
            HStack {
                Button("Load Sample Data") {
                    SampleData.load(into: modelContext)
                    sampleDataLoaded = true
                }
                .disabled(sampleDataLoaded)
                if sampleDataLoaded {
                    Spacer()
                    Text("Loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Delete All Data…", role: .destructive) {
                confirmDeleteAllData = true
            }
        }
        .confirmationDialog(
            "Delete all data? This cannot be undone.",
            isPresented: $confirmDeleteAllData,
            titleVisibility: .visible
        ) {
            Button("Delete All Data", role: .destructive) {
                try? SampleData.wipe(modelContext)
                sampleDataLoaded = false
            }
        }
    }
    #endif

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text(appName)
                Spacer()
                Text("Version \(shortVersion) (\(buildNumber))")
                    .foregroundStyle(.secondary)
            }
            Text(storageCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var storageCaption: String {
        AuthService.shared.isSignedIn
            ? "Synced to your account. Backups remain a good idea."
            : "Local-only storage. Export a backup before reinstalling."
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "TimeControl"
    }

    private var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
