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
        #if os(macOS)
        .overlay {
            if appState.isCommandPaletteShown {
                CommandPaletteView(isPresented: $appState.isCommandPaletteShown)
            }
        }
        .animation(.easeOut(duration: 0.18), value: appState.isCommandPaletteShown)
        #else
        .sheet(isPresented: $appState.isCommandPaletteShown) {
            CommandPaletteView(isPresented: $appState.isCommandPaletteShown)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        #endif
        .onAppear {
            modelContext.undoManager = undoManager
            rollOver()
            Task { await refreshBackgroundServices(requestingAuthorization: true) }
        }
        .onChange(of: undoManager) { _, new in modelContext.undoManager = new }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                rollOver()
                Task { await refreshBackgroundServices(requestingAuthorization: false) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in rollOver() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            NotificationScheduler.shared.scheduleRefresh(using: modelContext)
            if CalendarMirrorSettings.isEnabled {
                CalendarMirror.shared.scheduleSync(using: modelContext)
            }
        }
    }

    /// Re-plans local notifications. Asks for permission once, on first launch, when reminders are enabled.
    private func refreshBackgroundServices(requestingAuthorization: Bool) async {
        let scheduler = NotificationScheduler.shared
        await scheduler.refreshAuthorizationStatus()
        if requestingAuthorization, NotificationSettings.isEnabled, scheduler.authorizationStatus == .notDetermined {
            _ = await scheduler.requestAuthorization()
        }
        await scheduler.reschedule(using: modelContext)

        if CalendarMirrorSettings.isEnabled {
            do {
                try await CalendarMirror.shared.sync(using: modelContext)
            } catch {
                print("Calendar mirror sync failed: \(error)")
            }
        }
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
