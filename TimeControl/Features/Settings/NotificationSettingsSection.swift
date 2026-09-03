import SwiftData
import SwiftUI
import TimeControlCore
import UserNotifications
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The "Notifications" section of Settings: authorization status, the master reminders toggle, one
/// reminder-lead-time picker per kind, and the daily hour todos remind at.
struct NotificationSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @State private var authorizationStatus = NotificationScheduler.shared.authorizationStatus
    @State private var remindersEnabled = NotificationSettings.isEnabled
    @State private var todoDueHour = NotificationSettings.todoDueHour
    @State private var kindReminders: [Kind: Int?] = Dictionary(
        uniqueKeysWithValues: Kind.allCases.map { ($0, NotificationSettings.reminderMinutes(for: $0)) }
    )

    var body: some View {
        Section {
            authorizationRow

            Toggle("Reminders", isOn: $remindersEnabled)
                .onChange(of: remindersEnabled) { _, newValue in
                    NotificationSettings.isEnabled = newValue
                    reschedule()
                }

            if remindersEnabled {
                ForEach(Kind.allCases) { kind in
                    Picker(selection: reminderBinding(for: kind)) {
                        ForEach(NotificationSettings.reminderChoices, id: \.self) { minutes in
                            Text(NotificationSettings.label(forMinutes: minutes)).tag(minutes)
                        }
                    } label: {
                        Label(kind.displayName, systemImage: kind.symbolName)
                    }
                }

                Picker("Todo due reminders at", selection: $todoDueHour) {
                    ForEach(6...22, id: \.self) { hour in
                        Text(WeekMath.timeLabel(minute: hour * 60)).tag(hour)
                    }
                }
                .onChange(of: todoDueHour) { _, newValue in
                    NotificationSettings.todoDueHour = newValue
                    reschedule()
                }
            }
        } header: {
            Text("Notifications")
        }
        .task {
            await NotificationScheduler.shared.refreshAuthorizationStatus()
            authorizationStatus = NotificationScheduler.shared.authorizationStatus
        }
    }

    @ViewBuilder
    private var authorizationRow: some View {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            Label {
                Text("Allowed")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .denied:
            HStack {
                Label("Denied in System Settings", systemImage: "bell.slash")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open Settings") { openNotificationSettings() }
            }
        default:
            HStack {
                Label("Not asked yet", systemImage: "bell")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Enable Notifications") { requestAuthorization() }
            }
        }
    }

    private func reminderBinding(for kind: Kind) -> Binding<Int?> {
        Binding(
            get: { kindReminders[kind] ?? nil },
            set: { newValue in
                kindReminders[kind] = newValue
                NotificationSettings.setReminderMinutes(newValue, for: kind)
                reschedule()
            }
        )
    }

    private func requestAuthorization() {
        Task {
            _ = await NotificationScheduler.shared.requestAuthorization()
            authorizationStatus = NotificationScheduler.shared.authorizationStatus
            await NotificationScheduler.shared.reschedule(using: modelContext)
        }
    }

    private func reschedule() {
        Task { await NotificationScheduler.shared.reschedule(using: modelContext) }
    }

    private func openNotificationSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
        #endif
    }
}
