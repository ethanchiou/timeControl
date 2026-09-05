import SwiftData
import SwiftUI
import TimeControlCore

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Environment(\.scenePhase) private var scenePhase

    #if !os(macOS)
    /// Settings is not a tab on iOS; it is a sheet reached from Today and Terms, or by anything that
    /// sets `appState.section = .settings` (the `--section settings` flag, the command palette).
    @State private var showsSettings = false
    /// The tab to return to when the settings sheet closes.
    @State private var lastTab: AppSection = .today

    private var tabSelection: Binding<AppSection> {
        Binding(
            get: { appState.section == .settings ? lastTab : appState.section },
            set: { appState.section = $0 }
        )
    }
    #endif

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
            // Five tabs so none of them fold into "More"; Settings is a sheet instead.
            TabView(selection: tabSelection) {
                Tab(AppSection.today.title, systemImage: AppSection.today.symbolName, value: AppSection.today) {
                    TodayView()
                }
                Tab(AppSection.calendar.title, systemImage: AppSection.calendar.symbolName, value: AppSection.calendar) {
                    WeekView()
                }
                Tab(AppSection.todos.title, systemImage: AppSection.todos.symbolName, value: AppSection.todos) {
                    TodosView()
                }
                Tab(AppSection.projects.title, systemImage: AppSection.projects.symbolName, value: AppSection.projects) {
                    ProjectsView()
                }
                Tab(AppSection.terms.title, systemImage: AppSection.terms.symbolName, value: AppSection.terms) {
                    TermsView()
                }
            }
            .tabViewStyle(.sidebarAdaptable)
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
        .sheet(isPresented: $showsSettings, onDismiss: { appState.section = lastTab }) {
            SettingsView()
        }
        .onAppear {
            if appState.section == .settings { showsSettings = true }
        }
        .onChange(of: appState.section) { _, section in
            if section == .settings {
                showsSettings = true
            } else {
                lastTab = section
            }
        }
        #endif
        .onAppear {
            modelContext.undoManager = undoManager
            backUp()
            rollOver()
            Task { await refreshBackgroundServices(requestingAuthorization: true) }
        }
        .onChange(of: undoManager) { _, new in modelContext.undoManager = new }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                backUp()
                rollOver()
                Task { await refreshBackgroundServices(requestingAuthorization: false) }
            }
        }
        // A Mac left open across midnight never re-activates, so the day roll is its own trigger:
        // this is the moment yesterday's final state gets written.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            backUp()
            rollOver()
        }
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

    /// Writes the day's automatic backup. Runs before ``rollOver()``, which rewrites todo days in
    /// place, so the file keeps the schedule as the day actually ended.
    private func backUp() {
        AutoBackupService.runIfNeeded(in: modelContext)
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
        case .calendar: WeekView()
        case .todos: TodosView()
        case .projects: ProjectsView()
        case .terms: TermsView()
        case .settings: SettingsView()
        }
    }
}
