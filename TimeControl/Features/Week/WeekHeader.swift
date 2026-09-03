import SwiftUI
import TimeControlCore

/// Date range, term context and the week's navigation controls. Lives in-content on every platform
/// so the iOS tab and the macOS detail pane read the same.
struct WeekHeader: View {
    let days: ClosedRange<DayKey>
    let termName: String?
    let weekNumber: Int?
    let weekCount: Int?
    /// Occurrences in this week hidden by a blackout.
    let hiddenCount: Int

    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(dateRange)
                    .font(.headline)
                termLine
            }
            Spacer(minLength: 8)
            controls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

    // MARK: Controls

    private var controls: some View {
        @Bindable var appState = appState
        return HStack(spacing: 6) {
            Button {
                appState.shiftWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Previous week")
            .accessibilityLabel("Previous week")

            Button("Today") { appState.goToToday() }
                .help("This week")

            Button {
                appState.shiftWeek(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("Next week")
            .accessibilityLabel("Next week")

            Toggle(isOn: $appState.showsHiddenOccurrences) {
                if hiddenCount > 0 {
                    Label("\(hiddenCount) hidden", systemImage: eyeSymbol)
                } else {
                    Image(systemName: eyeSymbol)
                }
            }
            .toggleStyle(.button)
            .help(appState.showsHiddenOccurrences ? "Hide blacked-out occurrences" : "Show blacked-out occurrences")
            .accessibilityLabel(appState.showsHiddenOccurrences ? "Hide blacked-out occurrences" : "Show blacked-out occurrences")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var eyeSymbol: String {
        appState.showsHiddenOccurrences ? "eye" : "eye.slash"
    }

    // MARK: Date range

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
