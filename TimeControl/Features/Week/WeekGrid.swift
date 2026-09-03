import SwiftUI
import TimeControlCore

/// Seven day columns over a scrolling hour grid. All the maths lives in `WeekLayout`; this view only
/// turns minutes into points. The occurrences are handed in already computed for the week.
struct WeekGrid: View {
    let days: ClosedRange<DayKey>
    let occurrences: [Occurrence]
    let weeks: TermWeeks?
    let perform: @MainActor (WeekAction) -> Void

    @Environment(AppState.self) private var appState
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var didScroll = false

    private let gutter: CGFloat = 48
    private let hourHeight: CGFloat = 56
    private let minBlockHeight: CGFloat = 22

    private var dayList: [DayKey] { Array(days) }

    var body: some View {
        let plan = DayPlan(occurrences: occurrences)
        let hours = WeekLayout.hourRange(covering: plan.items)
        GeometryReader { geo in
            let flexible = max(0, geo.size.width - gutter) / 7
            let columnWidth = max(minColumnWidth, flexible)
            if columnWidth > flexible {
                ScrollView(.horizontal, showsIndicators: false) {
                    grid(columnWidth: columnWidth, hours: hours, plan: plan)
                }
            } else {
                grid(columnWidth: columnWidth, hours: hours, plan: plan)
            }
        }
    }

    /// The whole week at a known column width, so it can sit inside a horizontal scroll view when narrow.
    private func grid(columnWidth: CGFloat, hours: ClosedRange<Int>, plan: DayPlan) -> some View {
        VStack(spacing: 0) {
            headerRow(columnWidth: columnWidth)
            Divider()
            if !plan.allDay.isEmpty {
                allDayRow(columnWidth: columnWidth, plan: plan)
                Divider()
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    timeline(columnWidth: columnWidth, hours: hours, plan: plan)
                }
                .onAppear {
                    guard !didScroll else { return }
                    didScroll = true
                    // Hour rows are anchored by hour; the last one is `upperBound - 1`.
                    proxy.scrollTo(min(max(8, hours.lowerBound), hours.upperBound - 1), anchor: .top)
                }
            }
        }
        .frame(width: gutter + columnWidth * 7, alignment: .leading)
    }

    private var minColumnWidth: CGFloat {
        #if os(iOS)
        sizeClass == .compact ? 96 : 84
        #else
        84
        #endif
    }

    // MARK: Day headers

    private func headerRow(columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter, height: 1)
            ForEach(dayList, id: \.self) { day in
                dayHeader(day)
                    .frame(width: columnWidth)
                    .overlay(alignment: .leading) { columnSeparator }
            }
        }
        .background(.bar)
    }

    private func dayHeader(_ day: DayKey) -> some View {
        let isToday = day == DayKey.today()
        let isSelected = day == appState.selectedDay
        return Button {
            appState.show(day: day)
            appState.section = .today
        } label: {
            VStack(spacing: 3) {
                Text(day.weekday.shortName.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(day.day)")
                    .font(.callout.weight(isToday ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color.white : Color.primary)
                    .frame(width: 26, height: 26)
                    .background {
                        if isToday { Circle().fill(Color.accentColor) }
                    }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isSelected && !isToday ? Color.accentColor.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show \(day.weekday.name) in Today")
    }

    // MARK: All-day row

    private func allDayRow(columnWidth: CGFloat, plan: DayPlan) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("all-day")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: gutter - 6, alignment: .trailing)
                .padding(.trailing, 6)
                .padding(.top, 6)
            ForEach(dayList, id: \.self) { day in
                VStack(spacing: 2) {
                    ForEach(plan.allDay[day] ?? []) { occurrence in
                        OccurrenceBlock(occurrence: occurrence, height: 18, weeks: weeks, perform: perform)
                            .frame(height: 18)
                    }
                }
                .frame(width: columnWidth, alignment: .top)
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
                .overlay(alignment: .leading) { columnSeparator }
            }
        }
    }

    // MARK: Timeline

    private func timeline(columnWidth: CGFloat, hours: ClosedRange<Int>, plan: DayPlan) -> some View {
        let height = CGFloat(hours.upperBound - hours.lowerBound) * hourHeight
        return ZStack(alignment: .topLeading) {
            hourLines(hours: hours)
            HStack(spacing: 0) {
                gutterLabels(hours: hours)
                    .frame(width: gutter, height: height, alignment: .topLeading)
                ForEach(dayList, id: \.self) { day in
                    column(day: day, columnWidth: columnWidth, hours: hours, plan: plan)
                        .frame(width: columnWidth, height: height, alignment: .topLeading)
                        .overlay(alignment: .leading) { columnSeparator }
                }
            }
            currentTimeIndicator(columnWidth: columnWidth, hours: hours)
        }
        .frame(height: height, alignment: .topLeading)
        .padding(.bottom, 16)
    }

    /// Hour and half-hour rules. Each hour row carries its hour as a scroll anchor.
    private func hourLines(hours: ClosedRange<Int>) -> some View {
        VStack(spacing: 0) {
            ForEach(hours.lowerBound..<hours.upperBound, id: \.self) { hour in
                ZStack(alignment: .top) {
                    Rectangle().fill(.quaternary).frame(height: 0.5)
                    Rectangle().fill(.quinary).frame(height: 0.5).offset(y: hourHeight / 2)
                }
                .frame(height: hourHeight, alignment: .top)
                .id(hour)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(.quaternary).frame(height: 0.5)
        }
    }

    private func gutterLabels(hours: ClosedRange<Int>) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
            ForEach(hours, id: \.self) { hour in
                Text(hourLabel(hour))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .offset(x: -6, y: CGFloat(hour - hours.lowerBound) * hourHeight - 6)
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        WeekMath.instant(day: DayKey.epoch + hour / 24, minute: (hour % 24) * 60)
            .formatted(.dateTime.hour())
    }

    private func column(day: DayKey, columnWidth: CGFloat, hours: ClosedRange<Int>, plan: DayPlan) -> some View {
        let firstMinute = hours.lowerBound * 60
        return ZStack(alignment: .topLeading) {
            if day == appState.selectedDay {
                Rectangle().fill(Color.accentColor.opacity(0.04))
            } else {
                Color.clear
            }
            ForEach(plan.timed[day] ?? []) { occurrence in
                let item = LayoutItem(occurrence: occurrence)
                let slot = plan.slots[occurrence.id] ?? LayoutSlot(id: occurrence.id, column: 0, columnCount: 1)
                let share = (columnWidth - 4) / CGFloat(max(1, slot.columnCount))
                let blockHeight = max(minBlockHeight, CGFloat(item.endMinute - item.startMinute) / 60 * hourHeight)
                OccurrenceBlock(occurrence: occurrence, height: blockHeight, weeks: weeks, perform: perform)
                    .frame(width: max(12, share - 2), height: blockHeight, alignment: .topLeading)
                    .offset(
                        x: 2 + CGFloat(slot.column) * share,
                        y: CGFloat(item.startMinute - firstMinute) / 60 * hourHeight
                    )
            }
        }
    }

    @ViewBuilder
    private func currentTimeIndicator(columnWidth: CGFloat, hours: ClosedRange<Int>) -> some View {
        let today = DayKey.today()
        if days.contains(today) {
            TimelineView(.everyMinute) { context in
                let minute = WeekMath.minuteOfDay(context.date)
                let firstMinute = hours.lowerBound * 60
                if minute >= firstMinute, minute <= hours.upperBound * 60 {
                    HStack(spacing: 0) {
                        Circle()
                            .fill(.red)
                            .frame(width: 6, height: 6)
                        Rectangle()
                            .fill(.red)
                            .frame(height: 1)
                    }
                    .frame(width: columnWidth)
                    .offset(
                        x: gutter + CGFloat(today - days.lowerBound) * columnWidth,
                        y: CGFloat(minute - firstMinute) / 60 * hourHeight - 3
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var columnSeparator: some View {
        Rectangle().fill(.quaternary).frame(width: 0.5)
    }

    // MARK: Plan

    /// One pass over the week: split all-day items out, and pack each day's timed blocks side by side.
    private struct DayPlan {
        var allDay: [DayKey: [Occurrence]] = [:]
        var timed: [DayKey: [Occurrence]] = [:]
        var slots: [String: LayoutSlot] = [:]
        var items: [LayoutItem] = []

        init(occurrences: [Occurrence]) {
            for occurrence in occurrences {
                if occurrence.isAllDay {
                    allDay[occurrence.day, default: []].append(occurrence)
                } else {
                    timed[occurrence.day, default: []].append(occurrence)
                }
            }
            for list in timed.values {
                let dayItems = list.map(LayoutItem.init(occurrence:))
                items += dayItems
                for slot in WeekLayout.pack(dayItems) { slots[slot.id] = slot }
            }
        }
    }
}

private extension LayoutItem {
    /// An occurrence crossing midnight is clamped to the end of its own day.
    init(occurrence: Occurrence) {
        let start = WeekMath.minuteOfDay(occurrence.start)
        let end = WeekMath.minuteOfDay(occurrence.end)
        self.init(id: occurrence.id, startMinute: start, endMinute: end > start ? end : 24 * 60)
    }
}
