import SwiftData
import SwiftUI
import TimeControlCore

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager

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
        .onAppear { modelContext.undoManager = undoManager }
        .onChange(of: undoManager) { _, new in modelContext.undoManager = new }
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
