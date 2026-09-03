import SwiftUI
import TimeControlCore

/// A month as whole Monday-started weeks. Cells carry pills rather than time blocks: there is no room
/// for a timeline at this scale, so an occurrence shows as a one-line `OccurrenceBlock` (which already
/// collapses to its title at small heights) and a task as a `TodoChip`.
///
/// All the counting lives in `MonthLayout`; this view only turns rows and capacities into points.
struct MonthGrid: View {
    /// Whole weeks, from `DayKey.monthGrid`.
    let days: ClosedRange<DayKey>
    /// Days outside this day's month are drawn dimmed; they are still live.
    let monthOf: DayKey
    let occurrences: [Occurrence]
    /// Tasks by due date. Tasks with no due date do not reach the calendar.
    let todos: [DayKey: [TodoItem]]
    let weeks: TermWeeks?
    let perform: @MainActor (WeekAction) -> Void
    let onEditTodo: (TodoItem) -> Void

    @Environment(AppState.self) private var appState

    private let weekdayBarHeight: CGFloat = 22
    private let dateLineHeight: CGFloat = 20
    private let pillHeight: CGFloat = 17
    private let pillSpacing: CGFloat = 2

    private var byDay: [DayKey: [Occurrence]] {
        Dictionary(grouping: occurrences, by: \.day).mapValues { $0.sorted(by: Occurrence.displayOrder) }
    }

    var body: some View {
        let rows = MonthLayout.rows(in: days)
        let plan = byDay
        GeometryReader { geo in
            // The rows divide the height between them; nothing scrolls, because a vertical scroll
            // here is the gesture that pages to the next month.
            let available = geo.size.height - weekdayBarHeight - CGFloat(rows.count)
            let rowHeight = max(1, available / CGFloat(max(1, rows.count)))
            VStack(spacing: 0) {
                weekdayBar
                Divider()
                ForEach(rows.indices, id: \.self) { index in
                    weekRow(rows[index], height: rowHeight, plan: plan)
                    if index < rows.count - 1 { Divider() }
                }
            }
        }
    }

    // MARK: Weekday bar

    private var weekdayBar: some View {
        HStack(spacing: 0) {
            ForEach(Weekday.allCases, id: \.self) { weekday in
                Text(weekday.shortName.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: weekdayBarHeight)
        .background(.bar)
    }

    // MARK: Rows and cells

    private func weekRow(_ row: [DayKey], height: CGFloat, plan: [DayKey: [Occurrence]]) -> some View {
        HStack(spacing: 0) {
            ForEach(row, id: \.self) { day in
                cell(day, height: height, occurrences: plan[day] ?? [], todos: todos[day] ?? [])
                    .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
                    .overlay(alignment: .leading) {
                        if day != row.first { Rectangle().fill(.quaternary).frame(width: 0.5) }
                    }
            }
        }
    }

    private func cell(_ day: DayKey, height: CGFloat, occurrences: [Occurrence], todos: [TodoItem]) -> some View {
        let capacity = MonthLayout.capacity(
            cellHeight: height, dateHeight: dateLineHeight, pillHeight: pillHeight, spacing: pillSpacing
        )
        let total = occurrences.count + todos.count
        let split = MonthLayout.fit(count: total, capacity: capacity)
        let share = MonthLayout.share(slots: split.shown, occurrences: occurrences.count, todos: todos.count)
        let shownOccurrences = occurrences.prefix(share.occurrences)
        let shownTodos = todos.prefix(share.todos)

        return VStack(alignment: .leading, spacing: pillSpacing) {
            dateLine(day)
            ForEach(Array(shownOccurrences)) { occurrence in
                OccurrenceBlock(occurrence: occurrence, height: pillHeight, weeks: weeks, perform: perform)
                    .frame(height: pillHeight)
            }
            ForEach(Array(shownTodos), id: \.uuid) { todo in
                TodoChip(todo: todo, height: pillHeight, onEdit: onEditTodo)
            }
            if split.hidden > 0, capacity > 0 {
                moreButton(day, hidden: split.hidden)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(day == appState.selectedDay ? Color.accentColor.opacity(0.06) : Color.clear)
    }

    private func dateLine(_ day: DayKey) -> some View {
        let isToday = day == DayKey.today()
        let isInMonth = day.month == monthOf.month && day.year == monthOf.year
        return Button {
            appState.show(day: day)
            appState.calendarScale = .day
        } label: {
            HStack(spacing: 0) {
                Text(dayLabel(day))
                    .font(.caption.weight(isToday ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color.white : (isInMonth ? Color.primary : Color.secondary))
                    .padding(.horizontal, 5)
                    .frame(height: 17)
                    .background {
                        if isToday { Capsule().fill(Color.accentColor) }
                    }
                Spacer(minLength: 0)
            }
            .frame(height: dateLineHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show \(day.startDate().formatted(.dateTime.weekday(.wide).month(.wide).day()))")
    }

    /// The first of a month carries its name, so the eye can find the boundary in the padding weeks.
    private func dayLabel(_ day: DayKey) -> String {
        day.day == 1
            ? day.startDate().formatted(.dateTime.month(.abbreviated).day())
            : "\(day.day)"
    }

    private func moreButton(_ day: DayKey, hidden: Int) -> some View {
        Button {
            appState.show(day: day)
            appState.calendarScale = .day
        } label: {
            Text("+\(hidden) more")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: pillHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show this day")
    }
}
