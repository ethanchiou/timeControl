import SwiftData
import SwiftUI
import TimeControlCore

struct ProjectsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.sortOrder) private var projects: [Project]

    @State private var filter: ProjectStatus = .active
    @State private var showingNewProject = false
    @State private var editingProject: Project?
    @State private var pendingDelete: Project?

    private var filtered: [Project] {
        projects
            .filter { $0.status == filter }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.createdAt < rhs.createdAt
            }
    }

    private func count(for status: ProjectStatus) -> Int {
        projects.filter { $0.status == status }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Status", selection: $filter) {
                    ForEach(ProjectStatus.allCases) { status in
                        Text("\(status.title) \(count(for: status))").tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding()

                if filtered.isEmpty {
                    ContentUnavailableView {
                        Label("No \(filter.title.lowercased()) projects", systemImage: "square.grid.2x2")
                    } actions: {
                        Button("Add Project") { showingNewProject = true }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 16)], spacing: 16) {
                            ForEach(filtered) { project in
                                NavigationLink(value: project) {
                                    ProjectCard(project: project)
                                }
                                .buttonStyle(.plain)
                                .contextMenu { contextMenu(for: project) }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Projects")
            .navigationDestination(for: Project.self) { ProjectDetailView(project: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewProject = true
                    } label: {
                        Label("Add Project", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewProject) {
                ProjectEditorSheet(project: nil)
            }
            .sheet(item: $editingProject) { project in
                ProjectEditorSheet(project: project)
            }
            .confirmationDialog(
                deleteConfirmationTitle,
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let project = pendingDelete { modelContext.delete(project) }
                    pendingDelete = nil
                }
            }
        }
    }

    private var deleteConfirmationTitle: String {
        guard let project = pendingDelete else { return "" }
        let count = project.todos?.count ?? 0
        return "Delete \(project.title)? Its \(count) todos will be kept without a project."
    }

    @ViewBuilder
    private func contextMenu(for project: Project) -> some View {
        Button("Mark Active") { project.status = .active }
        Button("Pause") { project.status = .paused }
        Button("Mark Done") { project.status = .done }
        Divider()
        Button("Edit…") { editingProject = project }
        Button("Delete…", role: .destructive) { pendingDelete = project }
    }
}
