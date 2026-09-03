import SwiftUI

/// The eye. On: only one-time items show; course occurrences and events marked routine are hidden.
/// Shows how many routine items the current view is hiding when the caller knows.
struct RoutineFilterToggle: View {
    var hiddenCount: Int = 0

    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Toggle(isOn: $appState.hidesRoutine) {
            if appState.hidesRoutine, hiddenCount > 0 {
                Label("\(hiddenCount) routine hidden", systemImage: symbol)
            } else {
                Image(systemName: symbol)
            }
        }
        .toggleStyle(.button)
        .help(label)
        .accessibilityLabel(label)
    }

    private var symbol: String { appState.hidesRoutine ? "eye.slash" : "eye" }

    private var label: String {
        appState.hidesRoutine ? "Show routine items (courses and routine events)" : "Hide routine items, show only one-time items"
    }
}
