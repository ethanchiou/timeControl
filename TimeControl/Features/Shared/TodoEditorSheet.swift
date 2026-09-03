import SwiftData
import SwiftUI
import TimeControlCore

/// Create or edit a todo: title, priority, when (day / week / unscheduled), due date, project, notes.
struct TodoEditorSheet: View {
    enum Scope: Hashable { case unscheduled, day, week }

    let todo: TodoItem?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.sortOrder) private var projects: [Project]

    @State private var title: String
    @State private var notes: String
    @State private var priority: Priority
    @State private var scope: Scope
    @State private var scopeDate: Date
    @State private var hasDue: Bool
    @State private var dueDate: Date
    @State private var project: Project?
    @State private var confirmDelete = false

    init(todo: TodoItem? = nil, defaultDay: DayKey? = nil, defaultWeek: DayKey? = nil, defaultProject: Project? = nil) {
        self.todo = todo
        _title = State(initialValue: todo?.title ?? "")
        _notes = State(initialValue: todo?.notes ?? "")
        _priority = State(initialValue: Priority(clamping: todo?.priority ?? 3))
        let day = todo?.day ?? defaultDay
        let week = todo?.week ?? defaultWeek
        if let day {
            _scope = State(initialValue: .day)
            _scopeDate = State(initialValue: day.startDate())
        } else if let week {
            _scope = State(initialValue: .week)
            _scopeDate = State(initialValue: week.startDate())
        } else {
            _scope = State(initialValue: .unscheduled)
            _scopeDate = State(initialValue: DayKey.today().startDate())
        }
        _hasDue = State(initialValue: todo?.dueDay != nil)
        _dueDate = State(initialValue: (todo?.dueDay ?? .today()).startDate())
        _project = State(initialValue: todo?.project ?? defaultProject)
    }

    private var isEditing: Bool { todo != nil }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }
    private var activeProjects: [Project] {
        projects.filter { $0.status != .done || $0 == project }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, prompt: Text("What needs doing?"))
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases) { p in
                            Label(p.title, systemImage: p.symbolName).tag(p)
                        }
                    }
                }

                Section("When") {
                    Picker("Scope", selection: $scope) {
                        Text("Unscheduled").tag(Scope.unscheduled)
                        Text("Day").tag(Scope.day)
                        Text("Week").tag(Scope.week)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if scope != .unscheduled {
                        DatePicker(scope == .day ? "Day" : "Week of", selection: $scopeDate, displayedComponents: .date)
                        if scope == .week {
                            Text("Week of \(DayKey(scopeDate).weekStart.startDate().formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Due date", isOn: $hasDue)
                    if hasDue {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                }

                Section("Project") {
                    Picker("Project", selection: $project) {
                        Text("None").tag(Project?.none)
                        ForEach(activeProjects) { p in
                            Text(p.title).tag(Project?.some(p))
                        }
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if isEditing {
                    Section {
                        Button("Delete Todo", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Todo" : "New Todo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }.disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this todo?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let todo { modelContext.delete(todo) }
                    dismiss()
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 480)
        #else
        .presentationDetents([.large])
        #endif
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespaces)
        let item = todo ?? TodoItem(title: t)
        if todo == nil { modelContext.insert(item) }
        item.title = t
        item.notes = notes
        item.priority = priority.rawValue
        switch scope {
        case .unscheduled: item.unschedule()
        case .day: item.schedule(on: DayKey(scopeDate))
        case .week: item.schedule(inWeekOf: DayKey(scopeDate))
        }
        item.dueDay = hasDue ? DayKey(dueDate) : nil
        item.project = project
        dismiss()
    }
}
