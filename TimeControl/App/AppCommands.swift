import SwiftData
import SwiftUI

/// Menu bar commands shared by every window. Keyboard shortcuts live here so views stay simple.
struct AppCommands: Commands {
    let appState: AppState
    let container: ModelContainer

    var body: some Commands {
        #if DEBUG
        CommandMenu("Developer") {
            Button("Load Sample Data") { SampleData.load(into: container.mainContext) }
            Button("Delete All Data") { try? SampleData.wipe(container.mainContext) }
        }
        #endif
        CommandGroup(after: .newItem) {
            Button("Quick Add…") { appState.isCommandPaletteShown = true }
                .keyboardShortcut("k", modifiers: .command)
        }
        CommandMenu("Go") {
            Button("Today") { appState.goToToday() }
                .keyboardShortcut("t", modifiers: .command)
            Button("Previous Week") { appState.shiftWeek(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Next Week") { appState.shiftWeek(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous Day") { appState.shiftDay(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("Next Day") { appState.shiftDay(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Divider()
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { appState.section = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }
}
