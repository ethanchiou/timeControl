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
    }

    var body: some Scene {
        WindowGroup {
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
