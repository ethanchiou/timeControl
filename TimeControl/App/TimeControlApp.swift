import SwiftData
import SwiftUI
import TimeControlCore

@main
struct TimeControlApp: App {
    private let container: ModelContainer
    @State private var appState = AppState()

    init() {
        do {
            container = try ModelContainerFactory.make()
        } catch {
            fatalError("Could not open the TimeControl store: \(error)")
        }
        #if DEBUG
        if CommandLine.arguments.contains("--sample-data") {
            SampleData.load(into: container.mainContext)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--section"), i + 1 < CommandLine.arguments.count,
           let section = AppSection(rawValue: CommandLine.arguments[i + 1]) {
            appState.section = section
        }
        #endif
    }

    var body: some Scene {
        mainWindow
        #if os(macOS)
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
        .modelContainer(container)
        #endif
    }

    private var mainWindow: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(appState)
        }
        .modelContainer(container)
        .commands { AppCommands(appState: appState, container: container) }
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        #endif
    }
}
