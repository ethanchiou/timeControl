import SwiftData
import SwiftUI
import TimeControlCore

struct ProjectDetailView: View {
    @Bindable var project: Project

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var newTodoTitle = ""
    @State private var showsDone = false
    @State private var showingAddTodo = false
    @State private var showingEditProject = false
    @State private var editingTodo: TodoItem?
    @State private var confirmDeleteProject = false
    @FocusState private var addFieldFocused: Bool

    private var color: Color { Color(hex: project.colorHex) }

    var body: some View {
        List {
            headerSection
            Section("Summary") {
                TextField("Summary", text: $project.summary, axis: .vertical)
                    .lineLimit(2...4)
            }
            Section("Notes") {
                TextField("Notes", text: $project.notes, axis: .vertical)
                    .lineLimit(3...12)
            }
            todosSection
            doneSection
        }
        #if os(macOS)
        .listStyle(.inset)
        #endif
        .navigationTitle(project.title)
        #if os(macOS)
        .navigationSubtitle("\(project.progress.done) of \(project.progress.total) done")
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddTodo = true
                } label: {
                    Label("Add Todo", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit Project…") { showingEditProject = true }
                    Button(project.status == .done ? "Reopen" : "Mark Done") {
                        project.status = project.status == .done ? .active : .done
                    }
                    Button(project.status == .paused ? "Resume" : "Pause") {
                        project.status = project.status == .paused ? .active : .paused
                    }
                    Divider()
                    Button("Delete Project…", role: .destructive) { confirmDeleteProject = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddTodo) {
            TodoEditorSheet(defaultProject: project)
        }
        .sheet(isPresented: $showingEditProject) {
            ProjectEditorSheet(project: project)
        }
        .sheet(item: $editingTodo) { todo in
            TodoEditorSheet(todo: todo)
        }
        .confirmationDialog(
            "Delete \(project.title)? Its \(project.todos?.count ?? 0) todos will be kept without a project.",
            isPresented: $confirmDeleteProject,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                modelContext.delete(project)
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 16) {
                RingView(progress: project.progress, tint: color, label: .percent)
                    .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 6) {
                    Text(project.title)
                        .font(.title2.weight(.bold))
                    Picker("Status", selection: $project.status) {
                        ForEach(ProjectStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    PriorityBadge(priority: project.priority, compact: false)
                    Text(project.targetCountdown.text)
                        .font(.caption)
                        .foregroundStyle(project.targetCountdown.style)
                    if project.status == .done, let completedAt = project.completedAt {
                        Text("Completed \(completedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var todosSection: some View {
        Section("Todos") {
            if project.openTodos.isEmpty {
                Text("No open todos").foregroundStyle(.secondary)
            } else {
                ForEach(project.openTodos) { todo in
                    TodoRow(todo: todo, showsProject: false, showsDate: true)
                        .contextMenu {
                            Menu("Schedule") { ScheduleMenuItems(todo: todo) }
                            Button("Edit…") { editingTodo = todo }
                            Button("Delete", role: .destructive) { modelContext.delete(todo) }
                        }
                }
            }
            TextField("Add a todo to this project", text: $newTodoTitle)
                .focused($addFieldFocused)
                .onSubmit(addTodo)
        }
    }

    @ViewBuilder
    private var doneSection: some View {
        Section {
            DisclosureGroup("Done", isExpanded: $showsDone) {
                if project.doneTodos.isEmpty {
                    Text("No done todos").foregroundStyle(.secondary)
                } else {
                    ForEach(project.doneTodos) { todo in
                        TodoRow(todo: todo, showsProject: false, showsDate: false)
                    }
                }
            }
        }
    }

    private func addTodo() {
        let t = newTodoTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let item = TodoItem(title: t, project: project)
        modelContext.insert(item)
        newTodoTitle = ""
        addFieldFocused = true
    }
}
