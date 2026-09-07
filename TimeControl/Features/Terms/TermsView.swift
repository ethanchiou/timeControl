import SwiftData
import SwiftUI
import TimeControlCore

struct TermsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Term.startDayKey, order: .reverse) private var terms: [Term]

    @State private var showingNewTerm = false
    @State private var showsArchived = false
    @State private var pendingDelete: Term?

    private var activeTerms: [Term] { terms.filter { !$0.isArchived } }
    private var archivedTerms: [Term] { terms.filter { $0.isArchived } }

    var body: some View {
        NavigationStack {
            Group {
                if terms.isEmpty {
                    ContentUnavailableView {
                        Label { Text("No terms yet") } icon: { EmptyStateIllustration(.terms) }
                    } actions: {
                        Button("Add Term") { showingNewTerm = true }
                    }
                } else {
                    List {
                        ForEach(activeTerms) { term in
                            row(for: term)
                        }
                        if !archivedTerms.isEmpty {
                            DisclosureGroup("Archived", isExpanded: $showsArchived) {
                                ForEach(archivedTerms) { term in
                                    row(for: term)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Terms")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .navigationDestination(for: Term.self) { term in
                TermDetailView(term: term)
            }
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        appState.section = .settings
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewTerm = true
                    } label: {
                        Label("Add Term", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewTerm) {
                TermEditorSheet(term: nil)
            }
            .confirmationDialog(
                deleteConfirmationTitle,
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let term = pendingDelete { modelContext.delete(term) }
                    pendingDelete = nil
                }
            }
        }
    }

    private var deleteConfirmationTitle: String {
        guard let term = pendingDelete else { return "" }
        let count = term.sortedSeries.count
        return "Delete \(term.name) and its \(count) course\(count == 1 ? "" : "s")?"
    }

    @ViewBuilder
    private func row(for term: Term) -> some View {
        NavigationLink(value: term) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(term.name).font(.headline)
                    if term.contains(.today()) {
                        Text("Current")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(dateRangeLabel(for: term))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if term.contains(.today()), let week = term.weekNumber(of: .today()) {
                    Text("Week \(week) of \(term.weekCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .contextMenu {
            Button(term.isArchived ? "Unarchive" : "Archive") {
                term.isArchived.toggle()
            }
            Button("Delete", role: .destructive) {
                pendingDelete = term
            }
        }
        .swipeActions {
            Button("Delete", role: .destructive) {
                pendingDelete = term
            }
            Button(term.isArchived ? "Unarchive" : "Archive") {
                term.isArchived.toggle()
            }
            .tint(.orange)
        }
    }

    private func dateRangeLabel(for term: Term) -> String {
        let start = term.start.startDate().formatted(.dateTime.month().day())
        let end = term.end.startDate().formatted(.dateTime.month().day().year())
        return "\(start) – \(end) · \(term.weekCount) weeks"
    }
}
