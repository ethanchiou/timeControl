import SwiftUI
import TimeControlCore

/// Date range and term context for the visible span. On macOS it also carries the navigation controls;
/// on iOS those live in the navigation bar (see `WeekControls`) so the row stays on one line.
struct WeekHeader: View {
    let days: ClosedRange<DayKey>
    /// What the span means: a day, a week, or the weeks covering a month.
    let scale: CalendarScale
    let termName: String?
    let weekNumber: Int?
    let weekCount: Int?
    /// Occurrences in this week hidden by a blackout.
    let hiddenCount: Int

    var body: some View {
        #if os(macOS)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                termLine
            }
            Spacer(minLength: 8)
            ScalePicker()
            WeekControls(hiddenCount: hiddenCount)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        #else
        // One row: the range on the left, the term/week on the right. Both stay on a single line at 390pt.
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 6)
            termLine
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        #endif
    }

    // MARK: Term

    @ViewBuilder
    private var termLine: some View {
        if let termName {
            Text(weekLabel.map { "\(termName) · \($0)" } ?? termName)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("No term")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var weekLabel: String? {
        guard let weekNumber, let weekCount else { return nil }
        return "Week \(weekNumber) of \(weekCount)"
    }

    // MARK: Date range

    private var title: String {
        switch scale {
        case .day:
            return days.lowerBound.startDate().formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        case .month:
            // The span is whole weeks and spills either side, so name the month the grid is *of*,
            // which is always the month of the day two weeks in.
            return (days.lowerBound + 14).startDate().formatted(.dateTime.month(.wide).year())
        case .week:
            return dateRange
        }
    }

    /// "Sep 7 – 13, 2026", "Sep 28 – Oct 4, 2026" or "Dec 28, 2026 – Jan 3, 2027".
    private var dateRange: String {
        let first = days.lowerBound
        let last = days.upperBound
        let start = first.startDate()
        let end = last.startDate()
        if first.year != last.year {
            let a = start.formatted(.dateTime.month(.abbreviated).day().year())
            let b = end.formatted(.dateTime.month(.abbreviated).day().year())
            return "\(a) – \(b)"
        }
        let a = start.formatted(.dateTime.month(.abbreviated).day())
        let b = first.month == last.month
            ? end.formatted(.dateTime.day())
            : end.formatted(.dateTime.month(.abbreviated).day())
        return "\(a) – \(b), \(last.year)"
    }
}

/// Day / Week / Month. In the macOS header row; on iOS it sits in the navigation bar menu.
struct ScalePicker: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Picker("Scale", selection: $appState.calendarScale) {
            ForEach(CalendarScale.allCases) { scale in
                Text(scale.title).tag(scale)
            }
        }
        #if os(macOS)
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 190)
        .help("Show a day, a week or a month")
        #else
        // Segments would crowd the navigation bar off a 390pt screen; a menu costs one tap instead.
        .pickerStyle(.menu)
        .labelsHidden()
        .accessibilityLabel("Calendar scale")
        #endif
    }
}

/// Previous / today / next / show-hidden. In the macOS header row, in the iOS navigation bar.
struct WeekControls: View {
    /// Occurrences in the visible span hidden by a blackout.
    let hiddenCount: Int
    /// Compact iOS shows three days at a time, so its chevrons page by day rather than by week.
    var pagesByDay: Bool = false

    @Environment(AppState.self) private var appState

    /// Days moved by one chevron tap, or one swipe, when `pagesByDay`.
    static let dayPage = 3

    var body: some View {
        HStack(spacing: 6) {
            Button {
                shift(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Previous \(unitName)")
            .accessibilityLabel("Previous \(unitName)")

            #if os(macOS)
            Button("Today") { appState.goToToday() }
                .help("Jump to today")
            #else
            Button {
                appState.goToToday()
            } label: {
                Image(systemName: "calendar")
            }
            .accessibilityLabel("Today")
            #endif

            Button {
                shift(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("Next \(unitName)")
            .accessibilityLabel("Next \(unitName)")

            hiddenToggle
        }
        #if os(macOS)
        .buttonStyle(.bordered)
        .controlSize(.small)
        #endif
    }

    @ViewBuilder
    private var hiddenToggle: some View {
        #if os(macOS)
        @Bindable var appState = appState
        Toggle(isOn: $appState.showsHiddenOccurrences) {
            if hiddenCount > 0 {
                Label("\(hiddenCount) hidden", systemImage: eyeSymbol)
            } else {
                Image(systemName: eyeSymbol)
            }
        }
        .toggleStyle(.button)
        .help(hiddenToggleLabel)
        .accessibilityLabel(hiddenToggleLabel)
        #else
        Button {
            appState.showsHiddenOccurrences.toggle()
        } label: {
            Image(systemName: eyeSymbol)
        }
        .accessibilityLabel(hiddenToggleLabel)
        #endif
    }

    private func shift(_ pages: Int) {
        if pagesByDay, appState.calendarScale == .week {
            appState.shiftDay(by: pages * Self.dayPage)
        } else {
            appState.shiftCalendar(by: pages)
        }
    }

    /// What one chevron tap moves.
    private var unitName: String {
        if pagesByDay, appState.calendarScale == .week { return "days" }
        return appState.calendarScale.title.lowercased()
    }

    private var hiddenToggleLabel: String {
        appState.showsHiddenOccurrences ? "Hide blacked-out occurrences" : "Show blacked-out occurrences"
    }

    private var eyeSymbol: String {
        appState.showsHiddenOccurrences ? "eye" : "eye.slash"
    }
}
