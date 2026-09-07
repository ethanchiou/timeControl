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
    @State private var layout: Layout = .week
    @State private var courseDraft: CourseDraft?
    @State private var pendingDeleteSeries: Series?

    private enum Layout: Hashable {
        case week, courses
    }

    /// A new course started from the grid: where it was drawn, and the course it copies its details from.
    private struct CourseDraft: Identifiable {
        let id = UUID()
        var weekdays: Set<Weekday>
        var startMinute: Int
        var endMinute: Int
        var template: Series?
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Layout", selection: $layout) {
                Text("Week").tag(Layout.week)
                Text("Courses").tag(Layout.courses)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 240)
            .padding(.horizontal)
            .padding(.vertical, 8)
            switch layout {
            case .week: weekPane
            case .courses: list
            }
        }
        .navigationTitle(term.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
        .sheet(item: $courseDraft) { draft in
            SeriesEditorSheet(
                term: term,
                initialWeekdays: draft.weekdays,
                initialStartMinute: draft.startMinute,
                initialEndMinute: draft.endMinute,
                template: draft.template
            )
        }
        .confirmationDialog(
            deleteSeriesTitle,
            isPresented: Binding(get: { pendingDeleteSeries != nil }, set: { if !$0 { pendingDeleteSeries = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let series = pendingDeleteSeries { modelContext.delete(series) }
                pendingDeleteSeries = nil
            }
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

    private var list: some View {
        List {
            headerSection
            coursesSection
            blackoutsSection
        }
        #if os(macOS)
        .listStyle(.inset)
        #endif
    }

    // MARK: Week

    private var weekPane: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(weekCaption)
                Spacer()
                Text(gridHint)
                    .multilineTextAlignment(.trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.bottom, 8)
            Divider()
            TermWeekGrid(term: term, series: term.sortedSeries, perform: performGridAction)
        }
    }

    private var weekCaption: String {
        var caption = "\(dateRangeLabel) · \(term.weekCount) weeks"
        if term.contains(.today()), let week = term.weekNumber(of: .today()) {
            caption += " · Week \(week)"
        }
        return caption
    }

    private var gridHint: String {
        #if os(macOS)
        "Click or drag a free slot to add a course. Drag a block to move it; pull its bottom edge to change its length."
        #else
        "Tap a free slot to add a course. Press and hold a block to move it or pull its bottom edge."
        #endif
    }

    private func performGridAction(_ action: TermGridAction) {
        switch action {
        case .add(let weekday, let start, let end):
            courseDraft = CourseDraft(weekdays: [weekday], startMinute: start, endMinute: end, template: nil)
        case .edit(let series):
            editingSeries = series
        case .addAnotherTime(let series):
            courseDraft = CourseDraft(weekdays: [], startMinute: series.startMinute, endMinute: series.endMinute, template: series)
        case .delete(let series):
            pendingDeleteSeries = series
        case .move(let series, let from, let to, let start, let end):
            series.startMinute = start
            series.endMinute = end
            // Dragging one day's block onto another day moves just that day. Dropping it on a day the
            // course already meets would only merge two blocks into one, so the day change is ignored.
            if from != to, !series.weekdays.contains(to) {
                var days = series.weekdays
                days.remove(from)
                days.insert(to)
                series.weekdays = days
            }
        case .resize(let series, let end):
            series.endMinute = end
        }
    }

    private var deleteSeriesTitle: String {
        guard let series = pendingDeleteSeries else { return "" }
        return "Delete \(series.title) (\(series.scheduleSummary)) and all its occurrences?"
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

    /// One course: every time slot that shares a title.
    private struct CourseGroup: Identifiable {
        let title: String
        let series: [Series]
        var id: String { title }
    }

    private var groupedSeries: [CourseGroup] {
        var buckets: [String: [Series]] = [:]
        for series in term.sortedSeries {
            buckets[series.title, default: []].append(series)
        }
        return buckets.keys
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { CourseGroup(title: $0, series: buckets[$0] ?? []) }
    }

    @ViewBuilder
    private var coursesSection: some View {
        Section("Courses") {
            if term.sortedSeries.isEmpty {
                ContentUnavailableView {
                    Label { Text("No courses yet") } icon: { EmptyStateIllustration(.courses, size: 64) }
                } description: {
                    Text("Add one or press ⌘K and type: CS201 Mon/Wed 10-11:30 weeks 1-14")
                }
            } else {
                ForEach(groupedSeries) { group in
                    courseHeader(group)
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

    private func courseHeader(_ group: CourseGroup) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: group.series.first?.colorHex ?? group.series.first?.kind.colorHex ?? Kind.course.colorHex))
                .frame(width: 10, height: 10)
            Text(group.title).font(.headline)
            if let kind = group.series.first?.kind {
                Text(kind.displayName).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    /// One time slot of a course. The title sits on the group header above it.
    @ViewBuilder
    private func seriesRow(_ series: Series) -> some View {
        Button {
            editingSeries = series
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(series.scheduleSummary).font(.subheadline)
                Text(repeatCaption(series)).font(.caption).foregroundStyle(.secondary)
                if !series.location.isEmpty {
                    Text(series.location).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, 18)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Add Another Time…") {
                courseDraft = CourseDraft(weekdays: [], startMinute: series.startMinute, endMinute: series.endMinute, template: series)
            }
            Button("Delete Course…", role: .destructive) { pendingDeleteSeries = series }
        }
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
