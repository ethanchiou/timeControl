import SwiftData
import SwiftUI
import TimeControlCore

/// The week: header, grid, and every sheet, dialog and model edit a block can ask for.
///
/// Presentation lives here rather than in the blocks so a macOS popover can hand off to a sheet, and
/// so an iOS details sheet finishes dismissing before the next sheet or dialog goes up.
struct WeekView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @Query private var allSeries: [Series]
    @Query private var allEvents: [Event]
    @Query private var allBlackouts: [Blackout]
    @Query private var allExceptions: [OccurrenceException]
    @Query private var allTerms: [Term]

    @State private var sheet: Sheet?
    @State private var confirmation: Confirmation?
    @State private var pending: Presentation?
    @FocusState private var isGridFocused: Bool

    var body: some View {
        let all = snapshot.occurrences(in: days, includeSuppressed: true)
        let hiddenCount = all.filter(\.isSuppressed).count
        let shown = appState.showsHiddenOccurrences ? all : all.filter { !$0.isSuppressed }
        return Group {
            #if os(iOS)
            // The iOS TabView provides no navigation stack, and the week's controls live in the bar.
            NavigationStack { content(shown: shown, hiddenCount: hiddenCount) }
            #else
            content(shown: shown, hiddenCount: hiddenCount)
            #endif
        }
    }

    private func content(shown: [Occurrence], hiddenCount: Int) -> some View {
        Group {
            if allSeries.isEmpty, allEvents.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    WeekHeader(
                        days: days,
                        termName: term?.name,
                        weekNumber: weekNumber,
                        weekCount: term?.weekCount,
                        hiddenCount: hiddenCount
                    )
                    Divider()
                    grid(occurrences: shown)
                }
            }
        }
        .navigationTitle("Week")
        #if os(iOS)
        // Inline: the grid needs the vertical space, and the date range is already in the header row.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent(hiddenCount: hiddenCount) }
        #endif
        .sheet(item: $sheet, onDismiss: applyPending) { sheetContent($0) }
        .confirmationDialog(
            confirmation?.title ?? "",
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .visible,
            presenting: confirmation
        ) { confirmation in
            Button(confirmation.actionTitle, role: .destructive) { commit(confirmation) }
            Button("Cancel", role: .cancel) {}
        }
    }

    #if os(iOS)
    @ToolbarContentBuilder
    private func toolbarContent(hiddenCount: Int) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { appState.isCommandPaletteShown = true } label: {
                Label("Quick Add", systemImage: "command")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            WeekControls(hiddenCount: hiddenCount, pagesByDay: isCompact)
        }
    }

    private var isCompact: Bool { horizontalSizeClass == .compact }
    #endif

    // MARK: Data

    /// Built once per body evaluation; blocks never query for themselves.
    private var snapshot: ScheduleSnapshot {
        ScheduleSnapshot(series: allSeries, events: allEvents, blackouts: allBlackouts, exceptions: allExceptions)
    }

    /// The full week everywhere except compact iOS, which shows three days around the selected one so
    /// the columns stay readable and the time gutter never scrolls out of view.
    private var days: ClosedRange<DayKey> {
        #if os(iOS)
        if isCompact {
            return (appState.selectedDay - 1)...(appState.selectedDay + 1)
        }
        #endif
        return appState.weekStart...(appState.weekStart + 6)
    }

    private var term: Term? {
        allTerms.first { !$0.isArchived && ($0.contains(days.lowerBound) || $0.contains(days.upperBound)) }
    }

    /// The term week this row of days falls in; the term may start mid-week.
    private var weekNumber: Int? {
        guard let term else { return nil }
        return days.compactMap { term.weekNumber(of: $0) }.first
    }

    // MARK: Pieces

    @ViewBuilder
    private func grid(occurrences: [Occurrence]) -> some View {
        let grid = WeekGrid(days: days, occurrences: occurrences, weeks: term?.weeks, perform: perform)
        #if os(macOS)
        grid
            .focusable()
            .focusEffectDisabled()
            .focused($isGridFocused)
            .onAppear { isGridFocused = true }
            .onKeyPress(keys: ["t", .leftArrow, .rightArrow], phases: .down) { press in
                guard press.modifiers.isEmpty else { return .ignored }
                switch press.key {
                case .leftArrow: appState.shiftWeek(by: -1)
                case .rightArrow: appState.shiftWeek(by: 1)
                default: appState.goToToday()
                }
                return .handled
            }
        #else
        grid
        #endif
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No schedule yet", systemImage: "calendar.badge.plus")
        } description: {
            Text("Set up a term and add your courses, and they will fill this week.")
        } actions: {
            Button("Set Up a Term") { appState.section = .terms }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: Sheet) -> some View {
        switch sheet {
        case .details(let occurrence):
            OccurrenceDetailsCard(occurrence: occurrence, weeks: term?.weeks, perform: perform)
                .presentationDetents([.medium])
        case .editSeries(let series):
            if let term = series.term {
                SeriesEditorSheet(term: term, series: series)
            }
        case .editEvent(let event):
            EventEditorSheet(event: event)
        case .blackout(let term, let kind, let week):
            BlackoutEditorSheet(term: term, initialKinds: [kind], initialWeeks: week...week)
        }
    }

    // MARK: Actions

    private func perform(_ action: WeekAction) {
        switch action {
        case .showDetails(let occurrence):
            present(.sheet(.details(occurrence)))
        case .skip(let occurrence):
            guard let id = occurrence.seriesID else { return }
            modelContext.skip(seriesID: id, on: occurrence.day)
        case .editSeries(let occurrence):
            guard let id = occurrence.seriesID, let series = modelContext.series(uuid: id), series.term != nil else { return }
            present(.sheet(.editSeries(series)))
        case .editEvent(let occurrence):
            guard let id = occurrence.eventID, let event = modelContext.event(uuid: id) else { return }
            present(.sheet(.editEvent(event)))
        case .hideKindThisWeek(let occurrence):
            guard let term, let week = term.weekNumber(of: occurrence.day) else { return }
            present(.sheet(.blackout(term, occurrence.kind, week)))
        case .delete(let occurrence):
            present(.confirm(.delete(occurrence)))
        case .restore(let occurrence):
            present(.confirm(.restore(occurrence)))
        }
    }

    private func commit(_ confirmation: Confirmation) {
        switch confirmation {
        case .delete(let occurrence):
            modelContext.deleteSource(of: occurrence)
        case .restore(let occurrence):
            guard let id = occurrence.suppressedBy, let blackout = modelContext.blackout(uuid: id) else { return }
            modelContext.delete(blackout)
        }
        self.confirmation = nil
    }

    // MARK: Presentation

    private enum Presentation {
        case sheet(Sheet)
        case confirm(Confirmation)
    }

    /// A details sheet may already be up (iOS): let it finish dismissing, then present.
    private func present(_ presentation: Presentation) {
        if sheet != nil {
            pending = presentation
            sheet = nil
        } else {
            apply(presentation)
        }
    }

    private func apply(_ presentation: Presentation) {
        switch presentation {
        case .sheet(let next): sheet = next
        case .confirm(let next): confirmation = next
        }
    }

    private func applyPending() {
        guard let presentation = pending else { return }
        pending = nil
        apply(presentation)
    }

    enum Sheet: Identifiable {
        case details(Occurrence)
        case editSeries(Series)
        case editEvent(Event)
        case blackout(Term, Kind, Int)

        var id: String {
            switch self {
            case .details(let occurrence): "details-\(occurrence.id)"
            case .editSeries(let series): "series-\(series.uuid.uuidString)"
            case .editEvent(let event): "event-\(event.uuid.uuidString)"
            case .blackout(let term, let kind, let week): "blackout-\(term.uuid.uuidString)-\(kind.rawValue)-\(week)"
            }
        }
    }

    enum Confirmation: Identifiable {
        case delete(Occurrence)
        case restore(Occurrence)

        var id: String {
            switch self {
            case .delete(let occurrence): "delete-\(occurrence.id)"
            case .restore(let occurrence): "restore-\(occurrence.id)"
            }
        }

        var title: String {
            switch self {
            case .delete(let occurrence):
                occurrence.seriesID != nil
                    ? "Delete “\(occurrence.title)” and all of its occurrences?"
                    : "Delete “\(occurrence.title)”?"
            case .restore:
                "Remove the blackout hiding this occurrence?"
            }
        }

        var actionTitle: String {
            switch self {
            case .delete(let occurrence):
                occurrence.seriesID != nil ? "Delete \(occurrence.kind.displayName)" : "Delete Event"
            case .restore:
                "Remove Blackout"
            }
        }
    }
}
