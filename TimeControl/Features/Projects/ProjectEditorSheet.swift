import SwiftData
import SwiftUI
import TimeControlCore

/// Create or edit a project. Present as a sheet.
struct ProjectEditorSheet: View {
    static let swatches = ["#4F7CFF", "#A855F7", "#10B981", "#F59E0B", "#E5484D", "#06B6D4", "#EC4899", "#6B7280"]

    let project: Project?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.sortOrder) private var projects: [Project]

    @State private var title: String
    @State private var summary: String
    @State private var priority: Priority
    @State private var hasTarget: Bool
    @State private var targetDate: Date
    @State private var colorHex: String
    @State private var notes: String
    @State private var confirmDelete = false

    init(project: Project? = nil) {
        self.project = project
        _title = State(initialValue: project?.title ?? "")
        _summary = State(initialValue: project?.summary ?? "")
        _priority = State(initialValue: Priority(clamping: project?.priority ?? 3))
        _hasTarget = State(initialValue: project?.targetDay != nil)
        _targetDate = State(initialValue: (project?.targetDay ?? .today()).startDate())
        _colorHex = State(initialValue: project?.colorHex ?? Self.swatches[0])
        _notes = State(initialValue: project?.notes ?? "")
    }

    private var isEditing: Bool { project != nil }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, prompt: Text("Project title"))
                        .onSubmit { if canSave { save() } }
                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases) { p in
                            Label(p.title, systemImage: p.symbolName).tag(p)
                        }
                    }
                }

                Section {
                    Toggle("Target date", isOn: $hasTarget)
                    if hasTarget {
                        DatePicker("Target date", selection: $targetDate, displayedComponents: .date)
                    }
                }

                Section("Color") {
                    swatchRow
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...12)
                }

                if isEditing {
                    Section {
                        Button("Delete Project", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Project" : "New Project")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }.keyboardShortcut(.defaultAction).disabled(!canSave)
                }
            }
            .confirmationDialog(deleteConfirmationTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let project { modelContext.delete(project) }
                    dismiss()
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #else
        .presentationDetents([.large])
        #endif
    }

    private var deleteConfirmationTitle: String {
        guard let project else { return "" }
        let count = project.todos?.count ?? 0
        return "Delete \(project.title)? Its \(count) todos will be kept without a project."
    }

    private var swatchRow: some View {
        HStack(spacing: 12) {
            ForEach(Self.swatches, id: \.self) { hex in
                Button {
                    colorHex = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 28, height: 28)
                        .overlay {
                            if colorHex == hex {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespaces)
        let day = hasTarget ? DayKey(targetDate) : nil
        if let project {
            project.title = t
            project.summary = summary
            project.priority = priority.rawValue
            project.targetDay = day
            project.colorHex = colorHex
            project.notes = notes
        } else {
            let nextSortOrder = (projects.map(\.sortOrder).max() ?? -1) + 1
            let newProject = Project(title: t, summary: summary, priority: priority.rawValue, targetDay: day, colorHex: colorHex, sortOrder: nextSortOrder)
            newProject.notes = notes
            modelContext.insert(newProject)
        }
        dismiss()
    }
}
