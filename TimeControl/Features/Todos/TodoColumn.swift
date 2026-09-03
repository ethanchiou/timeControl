import SwiftData
import SwiftUI
import TimeControlCore

/// One bucket of todos: a ring + count header, a list you can drop todos into, and an inline add field.
/// The caller owns the todos and decides what a drop into this column means.
struct TodoColumn: View {
    let title: String
    /// Second line under the title; used for the week ring's caveat.
    var subtitle: String?
    /// `nil` shows a count instead of a ring.
    var ring: RingProgress?
    let todos: [TodoItem]
    let emptyHint: String
    /// Resolves a dragged uuid string back to a todo. Built once by `TodosView`.
    var lookup: [UUID: TodoItem] = [:]
    let onAdd: (String) -> Void
    let onDrop: (TodoItem) -> Void
    let onEdit: (TodoItem) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var showsDone = true
    @State private var draft = ""
    @FocusState private var isAddFocused: Bool

    private var visibleTodos: [TodoItem] {
        showsDone ? todos : todos.filter { !$0.isDone }
    }

    private var countCaption: String {
        if let ring {
            return "\(ring.done) of \(ring.total) done"
        }
        return todos.count == 1 ? "1 todo" : "\(todos.count) todos"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            list
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if let ring {
                RingView(progress: ring, lineWidth: 7, tint: RingPalette.color(for: ring), label: .fraction)
                    .frame(width: 64, height: 64)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(countCaption)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle(isOn: $showsDone) {
                Text("Show done").font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .fixedSize()
            .help("Show completed todos")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        List {
            if visibleTodos.isEmpty {
                Text(emptyHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .listRowSeparator(.hidden)
            }
            ForEach(visibleTodos) { todo in
                row(todo)
            }
            addField
        }
        .listStyle(.plain)
        .dropDestination(for: String.self) { payloads, _ in
            let dropped = resolve(payloads)
            guard !dropped.isEmpty else { return false }
            withAnimation(.snappy) {
                for todo in dropped {
                    onDrop(todo)
                    // Let go over empty space: send it to the end of this bucket.
                    TodoItem.reorder(todo, before: nil, in: todos)
                }
            }
            return true
        }
    }

    @ViewBuilder
    private func row(_ todo: TodoItem) -> some View {
        HStack(spacing: 6) {
            TodoGrip()
                .draggable(todo.uuid.uuidString)
            TodoRow(todo: todo, showsProject: true)
            if appState.rolledOverTodoIDs.contains(todo.uuid) {
                Image(systemName: "arrow.uturn.forward.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Rolled over")
                    .accessibilityLabel("Rolled over")
            }
        }
        .contentShape(.rect)
        // Dropping onto a row puts the dragged todo in this bucket at that row's position; the
        // list's own drop destination below catches anything let go over empty space.
        .dropDestination(for: String.self) { payloads, _ in
            guard let dragged = resolve(payloads).first else { return false }
            withAnimation(.snappy) {
                onDrop(dragged)
                TodoItem.reorder(dragged, before: todo, in: todos)
            }
            return true
        }
        .contextMenu {
            Menu("Schedule") { ScheduleMenuItems(todo: todo) }
            Button("Edit…") { onEdit(todo) }
            Divider()
            Button("Delete", role: .destructive) { delete(todo) }
        }
        #if os(iOS)
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) { delete(todo) }
        }
        #endif
    }

    @ViewBuilder
    private var addField: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            TextField("Add todo", text: $draft)
                .textFieldStyle(.plain)
                .focused($isAddFocused)
                .onSubmit(submit)
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
    }

    // MARK: Actions

    private func resolve(_ payloads: [String]) -> [TodoItem] {
        payloads.compactMap { UUID(uuidString: $0).flatMap { lookup[$0] } }
    }

    private func submit() {
        let title = draft.trimmingCharacters(in: .whitespaces)
        draft = ""
        guard !title.isEmpty else { return }
        withAnimation(.snappy) { onAdd(title) }
        // Keep the caret here so a run of todos can be typed without reaching for the mouse.
        isAddFocused = true
    }

    private func delete(_ todo: TodoItem) {
        withAnimation(.snappy) { modelContext.delete(todo) }
    }
}

#Preview {
    let container = try! ModelContainerFactory.make(inMemory: true)
    let context = container.mainContext
    let day = DayKey.today()
    let todos = [
        TodoItem(title: "Read chapter 4", priority: 1, day: day),
        TodoItem(title: "Email the TA about the lab slot", day: day),
        TodoItem(title: "Print the problem set", priority: 4, day: day)
    ]
    for todo in todos { context.insert(todo) }
    todos[2].setDone(true)
    return TodoColumn(
        title: "Day",
        ring: RingMath.daily(todos.map(\.spec), on: day),
        todos: todos,
        emptyHint: "Nothing planned for this day.",
        onAdd: { _ in },
        onDrop: { _ in },
        onEdit: { _ in }
    )
    .frame(width: 340, height: 420)
    .environment(AppState())
    .modelContainer(container)
}
