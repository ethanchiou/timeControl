import SwiftUI

/// The eye. A menu of two toggles: hide routine items (course occurrences and events marked
/// routine) and hide group items (events shared through a group). Shows how many items the
/// current view is hiding when the caller knows.
struct RoutineFilterToggle: View {
    var hiddenCount: Int = 0

    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Menu {
            Toggle("Hide routine", isOn: $appState.hidesRoutine)
            Toggle("Hide group", isOn: $appState.hidesGroup)
        } label: {
            if isFiltering, hiddenCount > 0 {
                Label("\(hiddenCount) hidden", systemImage: symbol)
            } else {
                Image(systemName: symbol)
            }
        }
        .help(label)
        .accessibilityLabel(label)
    }

    private var isFiltering: Bool { appState.hidesRoutine || appState.hidesGroup }
    private var symbol: String { isFiltering ? "eye.slash" : "eye" }

    private var label: String {
        isFiltering ? "Some items are hidden. Choose what the eye hides." : "Hide routine or group items"
    }
}
