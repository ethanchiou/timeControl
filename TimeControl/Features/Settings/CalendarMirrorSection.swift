import EventKit
import SwiftData
import SwiftUI
import TimeControlCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The "Apple Calendar" section of Settings: the master mirror toggle, per-kind mirroring, alarms,
/// and a manual sync trigger.
struct CalendarMirrorSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @State private var isEnabled = CalendarMirrorSettings.isEnabled
    @State private var alarmsEnabled = CalendarMirrorSettings.alarmsEnabled
    @State private var mirroredKinds: [Kind: Bool] = Dictionary(
        uniqueKeysWithValues: Kind.allCases.map { ($0, CalendarMirrorSettings.isMirrored($0)) }
    )
    @State private var lastSyncDate = CalendarMirrorSettings.lastSyncDate
    @State private var isSyncing = false
    @State private var syncSummary: String?
    @State private var accessDenied = false
    @State private var confirmDisable = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            Toggle("Mirror schedule to Apple Calendar", isOn: enabledBinding)

            if accessDenied {
                HStack {
                    Label("Calendar access denied", systemImage: "calendar.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings") { openCalendarSettings() }
                }
            }

            if isEnabled {
                ForEach(Kind.allCases) { kind in
                    Toggle("Mirror \(kind.pluralName)", isOn: mirroredBinding(for: kind))
                }

                Toggle("Add alarms", isOn: $alarmsEnabled)
                    .onChange(of: alarmsEnabled) { _, newValue in
                        CalendarMirrorSettings.alarmsEnabled = newValue
                        syncNow()
                    }

                HStack {
                    Button("Sync Now") { syncNow() }
                        .disabled(isSyncing)
                    if isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                    Text(syncCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Apple Calendar")
        } footer: {
            Text("One-way mirror into a calendar named “TimeControl”. Edits made in Calendar are overwritten on the next sync.")
        }
        .confirmationDialog(
            "Remove the TimeControl calendar and its events?",
            isPresented: $confirmDisable,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { disable(deleteCalendar: true) }
            Button("Keep events") { disable(deleteCalendar: false) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Calendar Sync Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                if newValue {
                    enable()
                } else {
                    confirmDisable = true
                }
            }
        )
    }

    private var syncCaption: String {
        if let syncSummary { return syncSummary }
        if let lastSyncDate {
            return "Last synced \(lastSyncDate.formatted(.relative(presentation: .named)))"
        }
        return "Never synced"
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func mirroredBinding(for kind: Kind) -> Binding<Bool> {
        Binding(
            get: { mirroredKinds[kind] ?? CalendarMirrorSettings.isMirrored(kind) },
            set: { newValue in
                mirroredKinds[kind] = newValue
                CalendarMirrorSettings.setMirrored(newValue, for: kind)
                syncNow()
            }
        )
    }

    private func enable() {
        accessDenied = false
        Task {
            let granted = await CalendarMirror.shared.requestAccess()
            guard granted else {
                accessDenied = true
                return
            }
            CalendarMirrorSettings.isEnabled = true
            isEnabled = true
            await performSync()
        }
    }

    private func disable(deleteCalendar: Bool) {
        CalendarMirrorSettings.isEnabled = false
        isEnabled = false
        syncSummary = nil
        guard deleteCalendar else { return }
        Task {
            do {
                try await CalendarMirror.shared.removeAll(deleteCalendar: true)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func syncNow() {
        guard !isSyncing else { return }
        Task { await performSync() }
    }

    private func performSync() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let summary = try await CalendarMirror.shared.sync(using: modelContext)
            lastSyncDate = CalendarMirrorSettings.lastSyncDate
            syncSummary = summaryText(summary)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func summaryText(_ summary: CalendarMirror.Summary) -> String {
        var parts: [String] = []
        if summary.created > 0 { parts.append("\(summary.created) created") }
        if summary.updated > 0 { parts.append("\(summary.updated) updated") }
        if summary.deleted > 0 { parts.append("\(summary.deleted) deleted") }
        return parts.isEmpty ? "Synced · up to date" : "Synced · \(parts.joined(separator: ", "))"
    }

    private func openCalendarSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
        #endif
    }
}
