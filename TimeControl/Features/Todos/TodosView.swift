import SwiftData
import SwiftUI
import TimeControlCore

/// Three buckets for one day: what is planned for the day, what is loose in the week, and the backlog.
/// Todos move between them by dragging, by the schedule menu, or by the editor sheet.
struct TodosView: View {
    private enum Bucket: String, CaseIterable, Identifiable {
        case day, week, backlog

        var id: String { rawValue }

        var title: String {
            switch self {
            case .day: "Day"
            case .week: "Week"
            case .backlog: "Backlog"
            }
        }
    }

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @Query(sort: \TodoItem.sortOrder) private var todos: [TodoItem]

    @State private var bucket: Bucket = .day
    @State private var showsBacklog = true
    @State private var showingNewTodo = false
    @State private var editingTodo: TodoItem?

    private var day: DayKey { appState.selectedDay }

    private var isRegular: Bool {
        #if os(macOS)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    // MARK: Buckets

    private var dayTodos: [TodoItem] {
        todos.filter { $0.day == day }.sorted(by: TodoItem.listOrder)
    }

    private var weekTodos: [TodoItem] {
        todos.filter { $0.week == day.weekStart && $0.day == nil }.sorted(by: TodoItem.listOrder)
    }

    private var backlogTodos: [TodoItem] {
        todos.filter { $0.day == nil && $0.week == nil }.sorted(by: TodoItem.listOrder)
    }

    private var specs: [TodoSpec] { todos.map(\.spec) }

    private var lookup: [UUID: TodoItem] {
        Dictionary(todos.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                if isRegular {
                    regularColumns
                } else {
                    compactColumn
                }
            }
            .navigationTitle("Todos")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewTodo = true
                    } label: {
                        Label("New Todo", systemImage: "plus")
                    }
                }
                if isRegular {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            withAnimation(.snappy) { showsBacklog.toggle() }
                        } label: {
                            Label("Backlog", systemImage: "sidebar.trailing")
                        }
                        .help(showsBacklog ? "Hide the backlog" : "Show the backlog")
                    }
                }
                #if os(macOS)
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Roll Over Now") { rollOverNow() }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
                #endif
            }
            .sheet(isPresented: $showingNewTodo) {
                TodoEditorSheet(defaultDay: appState.selectedDay)
            }
            .sheet(item: $editingTodo) { todo in
                TodoEditorSheet(todo: todo)
            }
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayTitle)
                    .font(.title2.weight(.semibold))
                Text("Week of \(weekTitle)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Button {
                    appState.shiftDay(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Previous day")
                .accessibilityLabel("Previous day")

                Button("Today") { appState.goToToday() }

                Button {
                    appState.shiftDay(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Next day")
                .accessibilityLabel("Next day")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var dayTitle: String {
        day.startDate().formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var weekTitle: String {
        day.weekStart.startDate().formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: Layouts

    @ViewBuilder
    private var regularColumns: some View {
        HStack(spacing: 0) {
            column(.day)
            Divider()
            column(.week)
            if showsBacklog {
                Divider()
                column(.backlog)
                    .frame(width: 260)
            }
        }
    }

    @ViewBuilder
    private var compactColumn: some View {
        VStack(spacing: 0) {
            Picker("Bucket", selection: $bucket) {
                ForEach(Bucket.allCases) { bucket in
                    Text(bucket.title).tag(bucket)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            column(bucket)
        }
    }

    @ViewBuilder
    private func column(_ bucket: Bucket) -> some View {
        switch bucket {
        case .day:
            TodoColumn(
                title: "Day",
                ring: RingMath.daily(specs, on: day),
                todos: dayTodos,
                emptyHint: "Nothing planned for this day. Drag from Week or Backlog, or type below.",
                lookup: lookup,
                onAdd: { add($0, to: .day) },
                onDrop: { $0.schedule(on: day) },
                onEdit: { editingTodo = $0 }
            )
        case .week:
            TodoColumn(
                title: "Week",
                subtitle: "incl. todos on days this week",
                ring: RingMath.weekly(specs, weekOf: day),
                todos: weekTodos,
                emptyHint: "Nothing loose in this week. Drag from Backlog, or type below.",
                lookup: lookup,
                onAdd: { add($0, to: .week) },
                onDrop: { $0.schedule(inWeekOf: day) },
                onEdit: { editingTodo = $0 }
            )
        case .backlog:
            TodoColumn(
                title: "Backlog",
                todos: backlogTodos,
                emptyHint: "The backlog is empty. Anything unscheduled lands here.",
                lookup: lookup,
                onAdd: { add($0, to: .backlog) },
                onDrop: { $0.unschedule() },
                onEdit: { editingTodo = $0 }
            )
        }
    }

    // MARK: Actions

    private func add(_ title: String, to bucket: Bucket) {
        let todo: TodoItem
        switch bucket {
        case .day: todo = TodoItem(title: title, day: day)
        case .week: todo = TodoItem(title: title, week: day)
        case .backlog: todo = TodoItem(title: title)
        }
        modelContext.insert(todo)
    }

    #if os(macOS)
    private func rollOverNow() {
        let moved = RolloverService.run(in: modelContext)
        appState.rolledOverTodoIDs.formUnion(moved.map(\.uuid))
    }
    #endif
}

#Preview {
    let container = try! ModelContainerFactory.make(inMemory: true)
    let context = container.mainContext
    let day = DayKey.today()
    context.insert(TodoItem(title: "Read chapter 4", priority: 1, day: day))
    context.insert(TodoItem(title: "Email the TA", day: day))
    context.insert(TodoItem(title: "Draft the lab report", priority: 2, week: day))
    context.insert(TodoItem(title: "Renew library books"))
    return TodosView()
        .environment(AppState())
        .modelContainer(container)
}
