import SwiftData
import SwiftUI
import TimeControlCore

struct TermDetailView: View {
    @Bindable var term: Term

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingEditTerm = false
    @State private var showingAddCourse = false
    @State private var showingClearWeeks = false
    @State private var editingSeries: Series?
    @State private var editingBlackout: Blackout?
    @State private var confirmDeleteTerm = false

    var body: some View {
        List {
            headerSection
            coursesSection
            blackoutsSection
        }
        #if os(macOS)
        .listStyle(.inset)
        #endif
        .navigationTitle(term.name)
        #if os(macOS)
        .navigationSubtitle(dateRangeLabel)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddCourse = true
                } label: {
                    Label("Add Course", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Clear Weeks…") { showingClearWeeks = true }
                    Button("Edit Term") { showingEditTerm = true }
                    Button(term.isArchived ? "Unarchive" : "Archive") {
                        term.isArchived.toggle()
                    }
                    Button("Delete Term", role: .destructive) {
                        confirmDeleteTerm = true
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditTerm) {
            TermEditorSheet(term: term)
        }
        .sheet(isPresented: $showingAddCourse) {
            SeriesEditorSheet(term: term)
        }
        .sheet(isPresented: $showingClearWeeks) {
            BlackoutEditorSheet(term: term)
        }
        .sheet(item: $editingSeries) { series in
            SeriesEditorSheet(term: term, series: series)
        }
        .sheet(item: $editingBlackout) { blackout in
            BlackoutEditorSheet(term: term, blackout: blackout)
        }
        .confirmationDialog(
            "Delete \(term.name) and its \(term.sortedSeries.count) course\(term.sortedSeries.count == 1 ? "" : "s")?",
            isPresented: $confirmDeleteTerm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                modelContext.delete(term)
                dismiss()
            }
        }
    }

    private var dateRangeLabel: String {
        let start = term.start.startDate().formatted(.dateTime.month().day())
        let end = term.end.startDate().formatted(.dateTime.month().day().year())
        return "\(start) – \(end)"
    }

    @ViewBuilder
    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(term.name).font(.title2.weight(.semibold))
                Text("\(dateRangeLabel) · \(term.weekCount) weeks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if term.contains(.today()), let week = term.weekNumber(of: .today()) {
                    Text("Week \(week) of \(term.weekCount)")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 2)

            Button("Edit Term") { showingEditTerm = true }

            Toggle("Archived", isOn: $term.isArchived)
        }
    }

    private struct WeekdayGroup: Identifiable {
        let weekday: Weekday
        let series: [Series]
        var id: Weekday { weekday }
    }

    private var groupedSeries: [WeekdayGroup] {
        var buckets: [Weekday: [Series]] = [:]
        for series in term.sortedSeries {
            guard let day = series.sortedWeekdays.first else { continue }
            buckets[day, default: []].append(series)
        }
        return Weekday.allCases.compactMap { day in
            guard let list = buckets[day], !list.isEmpty else { return nil }
            return WeekdayGroup(weekday: day, series: list)
        }
    }

    @ViewBuilder
    private var coursesSection: some View {
        Section("Courses") {
            if term.sortedSeries.isEmpty {
                ContentUnavailableView(
                    "No courses yet",
                    systemImage: "book.closed",
                    description: Text("Add one or press ⌘K and type: CS201 Mon/Wed 10-11:30 weeks 1-14")
                )
            } else {
                ForEach(groupedSeries) { group in
                    Text(group.weekday.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(group.series) { series in
                        seriesRow(series)
                    }
                }
            }
            Button {
                showingAddCourse = true
            } label: {
                Label("Add Course", systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private func seriesRow(_ series: Series) -> some View {
        Button {
            editingSeries = series
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Color(hex: series.colorHex ?? series.kind.colorHex))
                    .frame(width: 10, height: 10)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(series.title).font(.headline)
                    Text(series.scheduleSummary).font(.subheadline).foregroundStyle(.secondary)
                    Text(repeatCaption(series)).font(.caption).foregroundStyle(.secondary)
                    if !series.location.isEmpty {
                        Text(series.location).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func repeatCaption(_ series: Series) -> String {
        let every = series.isBiweekly ? "Every other week" : "Weekly"
        let weeks = series.startWeek == series.endWeek ? "week \(series.startWeek)" : "weeks \(series.startWeek)–\(series.endWeek)"
        return "\(every) · \(weeks)"
    }

    @ViewBuilder
    private var blackoutsSection: some View {
        Section {
            ForEach(term.sortedBlackouts) { blackout in
                blackoutRow(blackout)
            }
            Button {
                showingClearWeeks = true
            } label: {
                Label("Clear Weeks…", systemImage: "eye.slash")
            }
        } header: {
            Text("Blackouts")
        } footer: {
            Text("Blackouts hide recurring items without deleting them. Remove one to bring them back.")
        }
    }

    @ViewBuilder
    private func blackoutRow(_ blackout: Blackout) -> some View {
        Button {
            editingBlackout = blackout
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(blackout.summary).font(.headline)
                    if !blackout.reason.isEmpty {
                        Text(blackout.reason).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(blackoutDateRange(blackout)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button("Remove", role: .destructive) {
                modelContext.delete(blackout)
            }
        }
        .contextMenu {
            Button("Remove", role: .destructive) {
                modelContext.delete(blackout)
            }
        }
    }

    private func blackoutDateRange(_ blackout: Blackout) -> String {
        let start = blackout.start.startDate().formatted(.dateTime.month().day())
        let end = blackout.end.startDate().formatted(.dateTime.month().day())
        return "\(start) – \(end)"
    }
}
