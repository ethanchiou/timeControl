import SwiftData
import SwiftUI
import TimeControlCore

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var appState = appState
        Group {
            #if os(macOS)
            NavigationSplitView {
                List(AppSection.allCases, selection: $appState.section) { section in
                    Label(section.title, systemImage: section.symbolName)
                }
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
            } detail: {
                sectionView(appState.section)
            }
            #else
            TabView(selection: $appState.section) {
                ForEach(AppSection.allCases) { section in
                    sectionView(section)
                        .tabItem { Label(section.title, systemImage: section.symbolName) }
                        .tag(section)
                }
            }
            #endif
        }
        .onAppear {
            modelContext.undoManager = undoManager
            rollOver()
        }
        .onChange(of: undoManager) { _, new in modelContext.undoManager = new }
        .onChange(of: scenePhase) { _, phase in if phase == .active { rollOver() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in rollOver() }
    }

    /// Moves yesterday's unfinished todos onto today and marks them so the lists can flag them.
    private func rollOver() {
        let moved = RolloverService.run(in: modelContext)
        if !moved.isEmpty {
            appState.rolledOverTodoIDs.formUnion(moved.map(\.uuid))
        }
    }

    @ViewBuilder
    private func sectionView(_ section: AppSection) -> some View {
        switch section {
        case .today: TodayView()
        case .week: WeekView()
        case .todos: TodosView()
        case .projects: ProjectsView()
        case .terms: TermsView()
        case .settings: SettingsView()
        }
    }
}
