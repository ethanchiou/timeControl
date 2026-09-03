import SwiftData
import SwiftUI
import TimeControlCore

struct TodayView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @Query private var seriesList: [Series]
    @Query private var events: [Event]
    @Query private var blackouts: [Blackout]
    @Query private var exceptions: [OccurrenceException]
    @Query private var todos: [TodoItem]

    @State private var editingEvent: Event?
    @State private var isCreatingEvent = false
    @State private var editingTodo: TodoItem?
    @State private var isCreatingTodo = false
    @State private var editingSeries: Series?
    @State private var newTodoTitle = ""
    @FocusState private var addFieldFocused: Bool

    private var isRegularWidth: Bool {
        #if os(macOS)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    private var snapshot: ScheduleSnapshot {
        ScheduleSnapshot(series: seriesList, events: events, blackouts: blackouts, exceptions: exceptions)
    }

    private var occurrences: [Occurrence] {
        snapshot.occurrences(on: appState.selectedDay, hidingRoutine: appState.hidesRoutine)
    }

    private var dayTodos: [TodoItem] {
        todos.filter { $0.day == appState.selectedDay }.sorted(by: TodoItem.listOrder)
    }

    private var term: Term? { modelContext.currentTerm(on: appState.selectedDay) }

    private var dailyProgress: RingProgress { RingMath.daily(todos.map(\.spec), on: appState.selectedDay) }
    private var weeklyProgress: RingProgress { RingMath.weekly(todos.map(\.spec), weekOf: appState.selectedDay) }

    private var titleText: String {
        appState.selectedDay.startDate().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var relativeLabel: String? {
        switch appState.selectedDay - DayKey.today() {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default: nil
        }
    }

    private var termLabel: String? {
        guard let term, term.contains(appState.selectedDay), let week = term.weekNumber(of: appState.selectedDay) else { return nil }
        return "Week \(week) of \(term.weekCount) · \(term.name)"
    }

    private var subtitleText: String? {
        let parts = [relativeLabel, termLabel].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                #if !os(macOS)
                headerBlock
                #endif
                Group {
                    if isRegularWidth {
                        regularLayout
                    } else {
                        compactLayout
                    }
                }
            }
            .navigationTitle(titleText)
            #if os(macOS)
            .navigationSubtitle(subtitleText ?? "")
            #endif
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar { toolbarContent }
            .sheet(item: $editingEvent) { event in
                EventEditorSheet(event: event, defaultDay: appState.selectedDay)
            }
            .sheet(isPresented: $isCreatingEvent) {
                EventEditorSheet(event: nil, defaultDay: appState.selectedDay)
            }
            .sheet(item: $editingTodo) { todo in
                TodoEditorSheet(todo: todo)
            }
            .sheet(isPresented: $isCreatingTodo) {
                TodoEditorSheet(defaultDay: appState.selectedDay)
            }
            .sheet(item: $editingSeries) { series in
                if let term = series.term {
                    SeriesEditorSheet(term: term, series: series)
                }
            }
        }
    }

    // MARK: Toolbar / header

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(macOS)
        ToolbarItemGroup(placement: .navigation) {
            Button { appState.shiftDay(by: -1) } label: { Image(systemName: "chevron.left") }
            Button("Today") { appState.goToToday() }
            Button { appState.shiftDay(by: 1) } label: { Image(systemName: "chevron.right") }
        }
        #endif
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) {
            Button { appState.section = .settings } label: { Label("Settings", systemImage: "gearshape") }
        }
        ToolbarItem(placement: .topBarLeading) {
            Button { appState.isCommandPaletteShown = true } label: { Label("Quick Add", systemImage: "command") }
        }
        #endif
        ToolbarItem(placement: .primaryAction) {
            RoutineFilterToggle()
        }
        ToolbarItem(placement: .primaryAction) {
            Button { isCreatingEvent = true } label: { Label("New Event", systemImage: "calendar.badge.plus") }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { isCreatingTodo = true } label: { Label("New Todo", systemImage: "plus") }
        }
    }

    #if !os(macOS)
    private var headerBlock: some View {
        VStack(spacing: 6) {
            if let subtitleText {
                Text(subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button { appState.shiftDay(by: -1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Button("Today") { appState.goToToday() }
                    .buttonStyle(.bordered)
                Spacer()
                Button { appState.shiftDay(by: 1) } label: { Image(systemName: "chevron.right") }
            }
        }
        .padding()
    }
    #endif

    // MARK: Layout

    private var regularLayout: some View {
        GeometryReader { geo in
            HStack(alignment: .top, spacing: 20) {
                DayTimeline(
                    day: appState.selectedDay, occurrences: occurrences, term: term,
                    onEditEvent: { editingEvent = $0 }, onEditSeries: { editingSeries = $0 }
                )
                .frame(width: geo.size.width * 0.55)
                todoPane(scrollsInternally: true)
            }
            .padding()
        }
    }

    private var compactLayout: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    todoPane(scrollsInternally: false)
                    DayTimeline(
                        day: appState.selectedDay, occurrences: occurrences, term: term,
                        onEditEvent: { editingEvent = $0 }, onEditSeries: { editingSeries = $0 },
                        scrollsInternally: false
                    )
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: addFieldFocused) { _, focused in
                // Keep the add field above the keyboard; wait a beat for the keyboard's inset to land.
                guard focused else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(Self.addFieldID, anchor: .bottom)
                    }
                }
            }
        }
    }

    /// Scroll anchor for the inline add field.
    private static let addFieldID = "add-todo-field"

    // MARK: Todo pane

    @ViewBuilder
    private func todoPane(scrollsInternally: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ringSection
            if scrollsInternally {
                todoListSection
            } else {
                todoStack
            }
            addTodoField
        }
    }

    private var ringSection: some View {
        HStack(alignment: .center, spacing: 16) {
            RingView(progress: dailyProgress, lineWidth: 10, tint: RingPalette.color(for: dailyProgress))
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 8) {
                Text(dailyProgress.isEmpty ? "Nothing planned" : "\(dailyProgress.done) of \(dailyProgress.total) done")
                    .font(.headline)
                HStack(spacing: 8) {
                    RingView(progress: weeklyProgress, lineWidth: 6, tint: RingPalette.color(for: weeklyProgress), label: .percent)
                        .frame(width: 56, height: 56)
                    Text("This week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var todoListSection: some View {
        List {
            if dayTodos.isEmpty {
                Text("Nothing planned for this day")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dayTodos) { todo in
                    todoRow(todo)
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        .alternatingRowBackgrounds()
        #endif
    }

    /// Non-`List` rendering for the compact layout, which embeds the todo pane in the outer `ScrollView`
    /// (a `List` there collapses to zero height with no fixed frame to size against).
    @ViewBuilder
    private var todoStack: some View {
        if dayTodos.isEmpty {
            Text("Nothing planned for this day")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(dayTodos.enumerated()), id: \.element.uuid) { index, todo in
                    todoRow(todo)
                        .padding(.vertical, 6)
                    if index < dayTodos.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func todoRow(_ todo: TodoItem) -> some View {
        HStack(spacing: 6) {
            TodoGrip()
                .draggable(todo.uuid.uuidString)
            TodoRow(todo: todo)
            if appState.rolledOverTodoIDs.contains(todo.uuid) {
                Image(systemName: "arrow.uturn.forward.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Rolled over from an earlier day")
            }
        }
        .contentShape(.rect)
        .dropDestination(for: String.self) { payloads, _ in
            guard let dragged = resolveTodo(payloads) else { return false }
            withAnimation(.snappy) {
                // This pane is one day's list, so a drop only ever changes the order within it.
                TodoItem.reorder(dragged, before: todo, in: dayTodos)
            }
            return true
        }
        .contextMenu {
            Menu("Schedule") {
                ScheduleMenuItems(todo: todo)
            }
            Button("Edit…") { editingTodo = todo }
            Button("Delete", role: .destructive) { modelContext.delete(todo) }
        }
        .swipeActions {
            Button("Delete", role: .destructive) { modelContext.delete(todo) }
        }
    }

    private func resolveTodo(_ payloads: [String]) -> TodoItem? {
        guard let uuid = payloads.compactMap({ UUID(uuidString: $0) }).first else { return nil }
        return todos.first { $0.uuid == uuid }
    }

    private var addTodoField: some View {
        TextField("Add a todo for this day", text: $newTodoTitle)
            .textFieldStyle(.roundedBorder)
            .focused($addFieldFocused)
            .id(Self.addFieldID)
            #if !os(macOS)
            .submitLabel(.done)
            #endif
            .onSubmit {
                let trimmed = newTodoTitle.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                modelContext.insert(TodoItem(title: trimmed, day: appState.selectedDay))
                newTodoTitle = ""
                // The Mac keeps the caret for a run of todos; iOS gives the screen back instead.
                #if os(macOS)
                addFieldFocused = true
                #else
                addFieldFocused = false
                #endif
            }
    }
}
