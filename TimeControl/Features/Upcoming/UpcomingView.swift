import SwiftData
import SwiftUI
import TimeControlCore

/// The Upcoming section in its own stack, for the macOS sidebar and the iPad tab bar. The iPhone has
/// no tab for it and pushes `UpcomingView` from Today instead.
struct UpcomingSection: View {
    var body: some View {
        NavigationStack { UpcomingView() }
    }
}

/// What is still to come — the rest of today, the next seven days or the next thirty — grouped by
/// day. Opens on one-time items only; the eye reveals course occurrences and routine events.
///
/// The window is a pure function of the clock (`UpcomingAgenda`), so the list re-evaluates once a
/// minute and an item drops off as soon as it has ended.
struct UpcomingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @Query private var seriesList: [Series]
    @Query private var events: [Event]
    @Query private var blackouts: [Blackout]
    @Query private var exceptions: [OccurrenceException]
    @Query private var groups: [SharedGroup]

    @State private var editingEvent: Event?
    @State private var isCreatingEvent = false
    @State private var editingSeries: Series?
    @State private var pendingDelete: Occurrence?

    private var snapshot: ScheduleSnapshot {
        ScheduleSnapshot(series: seriesList, events: events, blackouts: blackouts, exceptions: exceptions, groups: groups)
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            agenda(now: context.date)
        }
        .navigationTitle("Upcoming")
        .sheet(item: $editingEvent) { event in
            EventEditorSheet(event: event)
        }
        .sheet(isPresented: $isCreatingEvent) {
            EventEditorSheet(event: nil, defaultDay: .today())
        }
        .sheet(item: $editingSeries) { series in
            if let term = series.term {
                SeriesEditorSheet(term: term, series: series)
            }
        }
        .confirmationDialog(
            "Delete this event?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let occurrence = pendingDelete { modelContext.deleteSource(of: occurrence) }
                pendingDelete = nil
            }
        }
    }

    // MARK: Agenda

    @ViewBuilder
    private func agenda(now: Date) -> some View {
        let today = DayKey(now)
        let days = UpcomingAgenda.days(for: appState.upcomingScale, from: today)
        let pending = UpcomingAgenda.pending(snapshot.occurrences(in: days), now: now, today: today)
        let filter = appState.hiddenFilter
        let shown = pending.filter { !filter.hides($0) }
        let groups = UpcomingAgenda.groups(shown)
        VStack(spacing: 0) {
            #if os(iOS)
            scalePicker
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
            #endif
            if groups.isEmpty {
                emptyState(hidden: pending.count - shown.count)
            } else {
                List {
                    ForEach(groups) { group in
                        Section(dayTitle(group.day, today: today)) {
                            ForEach(group.occurrences) { occurrence in
                                row(occurrence)
                            }
                        }
                    }
                }
                #if os(macOS)
                .listStyle(.inset)
                #endif
            }
        }
        .toolbar { toolbarContent(hidden: pending.count - shown.count) }
    }

    private var scalePicker: some View {
        @Bindable var appState = appState
        return Picker("Window", selection: $appState.upcomingScale) {
            ForEach(CalendarScale.allCases) { scale in
                Text(Self.windowTitle(scale)).tag(scale)
            }
        }
        .labelsHidden()
    }

    /// The segments say how far the window reaches, since a "week" here is the next seven days
    /// rather than the calendar's Monday-to-Sunday.
    static func windowTitle(_ scale: CalendarScale) -> String {
        switch scale {
        case .day: "Today"
        case .week: "7 Days"
        case .month: "30 Days"
        }
    }

    private static func windowDescription(_ scale: CalendarScale) -> String {
        switch scale {
        case .day: "the rest of today"
        case .week: "the next seven days"
        case .month: "the next thirty days"
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent(hidden: Int) -> some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) {
            scalePicker
                .pickerStyle(.segmented)
                .frame(width: 220)
                .help("How far ahead to look")
        }
        #endif
        ToolbarItem(placement: .primaryAction) {
            RoutineFilterToggle(hiddenCount: hidden)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { isCreatingEvent = true } label: { Label("New Event", systemImage: "calendar.badge.plus") }
        }
    }

    private func dayTitle(_ day: DayKey, today: DayKey) -> String {
        let date = day.startDate().formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        guard let name = UpcomingAgenda.relativeName(day, today: today) else { return date }
        return "\(name) · \(date)"
    }

    private func emptyState(hidden: Int) -> some View {
        ContentUnavailableView {
            Label { Text("Nothing coming up") } icon: { EmptyStateIllustration(.today) }
        } description: {
            if hidden > 0 {
                Text("Nothing one-time in \(Self.windowDescription(appState.upcomingScale)). The eye is hiding \(hidden) routine \(hidden == 1 ? "item" : "items").")
            } else {
                Text("Nothing scheduled for \(Self.windowDescription(appState.upcomingScale)).")
            }
        }
    }

    // MARK: Rows

    private func group(for occurrence: Occurrence) -> SharedGroup? {
        guard let groupID = occurrence.groupID else { return nil }
        return groups.first { $0.uuid == groupID }
    }

    private func row(_ occurrence: Occurrence) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if occurrence.isAllDay {
                    Text("All day")
                } else {
                    Text(WeekMath.timeLabel(minute: WeekMath.minuteOfDay(occurrence.start)))
                    Text(WeekMath.timeLabel(minute: WeekMath.minuteOfDay(occurrence.end)))
                }
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 64, alignment: .leading)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(hex: occurrence.colorHex))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(occurrence.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                if !occurrence.location.isEmpty {
                    Text(occurrence.location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if let group = group(for: occurrence) {
                    GroupChip(name: group.name, colorHex: group.effectiveColorHex)
                }
                KindBadge(kind: occurrence.kind, style: .pill)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { edit(occurrence) }
        .contextMenu { actions(for: occurrence) }
    }

    // MARK: Actions

    private func edit(_ occurrence: Occurrence) {
        switch occurrence.source {
        case .event(let id):
            editingEvent = modelContext.event(uuid: id)
        case .series(let seriesID, _):
            if let series = modelContext.series(uuid: seriesID), series.term != nil { editingSeries = series }
        }
    }

    @ViewBuilder
    private func actions(for occurrence: Occurrence) -> some View {
        switch occurrence.source {
        case .event:
            Button("Edit Event…") { edit(occurrence) }
            Button("Delete Event…", role: .destructive) { pendingDelete = occurrence }
        case .series(let seriesID, let day):
            Button("Skip This Occurrence") { modelContext.skip(seriesID: seriesID, on: day) }
            Button("Edit Course…") { edit(occurrence) }
        }
    }
}
