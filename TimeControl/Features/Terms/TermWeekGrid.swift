import SwiftUI
import TimeControlCore

/// What the term's week grid asks the term page to do. The page owns every sheet, dialog and model
/// edit, so the grid never touches the model context.
enum TermGridAction {
    case add(weekday: Weekday, startMinute: Int, endMinute: Int)
    case edit(Series)
    /// A new time slot for the same course: the sheet opens with the course's details copied in.
    case addAnotherTime(Series)
    case delete(Series)
    /// A block dragged elsewhere. `to` differs from `from` when it crossed into another day column.
    case move(Series, from: Weekday, to: Weekday, startMinute: Int, endMinute: Int)
    case resize(Series, endMinute: Int)
}

/// The term's timetable: one column per weekday and a block for every day a course meets. It is not a
/// calendar week — every course shows whatever its week range or interval, so the whole weekly pattern
/// can be laid out at once. Click or drag free space to add a course, drag a block to move it, pull the
/// bottom edge of a block to change its length; on iOS press and hold before dragging.
struct TermWeekGrid: View {
    let term: Term
    let series: [Series]
    let perform: @MainActor (TermGridAction) -> Void

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var drag: Drag?
    @State private var didScroll = false

    private let gutter: CGFloat = 48
    private let hourHeight: CGFloat = 56
    private let minBlockHeight: CGFloat = 22
    private let weekdays = Weekday.allCases

    var body: some View {
        let plan = Plan(series: series)
        let hours = WeekLayout.hourRange(covering: plan.items)
        GeometryReader { geo in
            let available = geo.size.width - DayGridMetrics.verticalScrollerInset
            let flexible = max(0, available - gutter) / CGFloat(weekdays.count)
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

    private var minColumnWidth: CGFloat {
        #if os(iOS)
        sizeClass == .compact ? 96 : 84
        #else
        84
        #endif
    }

    private func grid(columnWidth: CGFloat, hours: ClosedRange<Int>, plan: Plan) -> some View {
        // Leading: the scrolling half reports itself a scroller wider than the frame below, and a
        // centred stack would pay for that by pushing the header row off its own columns.
        VStack(alignment: .leading, spacing: 0) {
            headerRow(columnWidth: columnWidth)
            Divider()
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    timeline(columnWidth: columnWidth, hours: hours, plan: plan)
                        .padding(.top, 8)   // room for the first hour label, which sits 6pt above its rule
                }
                .onAppear {
                    guard !didScroll else { return }
                    didScroll = true
                    proxy.scrollTo(min(max(8, hours.lowerBound), hours.upperBound - 1), anchor: .top)
                }
            }
        }
        .frame(width: gutter + columnWidth * CGFloat(weekdays.count), alignment: .leading)
    }

    private func headerRow(columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter, height: 1)
            ForEach(weekdays, id: \.self) { day in
                Text(day.shortName.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: columnWidth)
                    .padding(.vertical, 9)
                    .overlay(alignment: .leading) { columnSeparator }
            }
        }
        .background(.bar)
    }

    // MARK: Timeline

    private func timeline(columnWidth: CGFloat, hours: ClosedRange<Int>, plan: Plan) -> some View {
        let height = CGFloat(hours.upperBound - hours.lowerBound) * hourHeight
        return ZStack(alignment: .topLeading) {
            HourLines(hours: hours, hourHeight: hourHeight)
            HStack(spacing: 0) {
                HourGutterLabels(hours: hours, hourHeight: hourHeight)
                    .frame(width: gutter, height: height, alignment: .topLeading)
                ForEach(weekdays, id: \.self) { day in
                    column(day: day, columnWidth: columnWidth, hours: hours, plan: plan)
                        .frame(width: columnWidth, height: height, alignment: .topLeading)
                        .overlay(alignment: .leading) { columnSeparator }
                }
            }
            ghost(columnWidth: columnWidth, hours: hours)
        }
        .frame(height: height, alignment: .topLeading)
        .padding(.bottom, 16)
    }

    private func column(day: Weekday, columnWidth: CGFloat, hours: ClosedRange<Int>, plan: Plan) -> some View {
        let firstMinute = hours.lowerBound * 60
        return ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 1, coordinateSpace: .local) { point in
                    let minute = TermGridMath.minute(atY: point.y, firstHour: hours.lowerBound, hourHeight: hourHeight)
                    let slot = TermGridMath.slot(forClickAt: minute)
                    perform(.add(weekday: day, startMinute: slot.start, endMinute: slot.end))
                }
                .gesture(pressDrag(
                    onChanged: { value in
                        drag = .creating(
                            weekday: day,
                            anchorMinute: TermGridMath.minute(atY: value.startLocation.y, firstHour: hours.lowerBound, hourHeight: hourHeight),
                            currentMinute: TermGridMath.minute(atY: value.location.y, firstHour: hours.lowerBound, hourHeight: hourHeight)
                        )
                    },
                    onEnded: { value in
                        drag = nil
                        let slot = TermGridMath.slot(
                            dragFrom: TermGridMath.minute(atY: value.startLocation.y, firstHour: hours.lowerBound, hourHeight: hourHeight),
                            to: TermGridMath.minute(atY: value.location.y, firstHour: hours.lowerBound, hourHeight: hourHeight)
                        )
                        perform(.add(weekday: day, startMinute: slot.start, endMinute: slot.end))
                    }
                ))
            ForEach(plan.byDay[day] ?? []) { block in
                let slot = plan.slots[block.id] ?? LayoutSlot(id: block.id, column: 0, columnCount: 1)
                let share = (columnWidth - 4) / CGFloat(max(1, slot.columnCount))
                let end = previewedEnd(of: block)
                let blockHeight = max(minBlockHeight, CGFloat(end - block.startMinute) / 60 * hourHeight)
                blockView(block, height: blockHeight, columnWidth: columnWidth)
                    .frame(width: max(12, share - 2), height: blockHeight, alignment: .topLeading)
                    .offset(
                        x: 2 + CGFloat(slot.column) * share,
                        y: CGFloat(block.startMinute - firstMinute) / 60 * hourHeight
                    )
                    .opacity(isMoving(block) ? 0.35 : 1)
            }
        }
    }

    // MARK: Blocks

    private func blockView(_ block: Block, height: CGFloat, columnWidth: CGFloat) -> some View {
        blockContent(block, height: height)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onTapGesture { perform(.edit(block.series)) }
            .gesture(pressDrag(
                onChanged: { value in drag = .moving(block, translation: value.translation) },
                onEnded: { value in commitMove(block, translation: value.translation, columnWidth: columnWidth) }
            ))
            .overlay(alignment: .bottom) { resizeHandle(block) }
            .contextMenu { blockMenu(block) }
    }

    private func blockContent(_ block: Block, height: CGFloat) -> some View {
        let color = color(of: block.series)
        return HStack(spacing: 0) {
            Rectangle()
                .fill(color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.series.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(height > 40 ? 2 : 1)
                if height > 40 {
                    Text(timeLabel(block.startMinute, previewedEnd(of: block)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if height > 60, let note = scheduleNote(block.series) {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if height > 78, !block.series.location.isEmpty {
                    Text(block.series.location)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help("\(block.series.title) · \(timeLabel(block.startMinute, block.endMinute))")
    }

    /// The bottom strip of a block: drag it to change the course's end time.
    private func resizeHandle(_ block: Block) -> some View {
        Color.clear
            .frame(height: 8)
            .contentShape(Rectangle())
            .gesture(pressDrag(
                onChanged: { value in drag = .resizing(block, minuteDelta: minutes(forPoints: value.translation.height)) },
                onEnded: { value in
                    drag = nil
                    let end = TermGridMath.resized(start: block.startMinute, end: block.endMinute, by: minutes(forPoints: value.translation.height))
                    if end != block.endMinute { perform(.resize(block.series, endMinute: end)) }
                }
            ))
            #if os(macOS)
            .pointerStyle(.frameResize(position: .bottom))
            #endif
    }

    @ViewBuilder
    private func blockMenu(_ block: Block) -> some View {
        Button {
            perform(.edit(block.series))
        } label: {
            Label("Edit Course…", systemImage: "pencil")
        }
        Button {
            perform(.addAnotherTime(block.series))
        } label: {
            Label("Add Another Time…", systemImage: "plus.square.on.square")
        }
        Divider()
        Button(role: .destructive) {
            perform(.delete(block.series))
        } label: {
            Label("Delete Course…", systemImage: "trash")
        }
    }

    private func commitMove(_ block: Block, translation: CGSize, columnWidth: CGFloat) {
        drag = nil
        let target = weekdays[TermGridMath.column(from: block.weekday.rawValue, dx: translation.width, columnWidth: columnWidth, count: weekdays.count)]
        let range = TermGridMath.moved(start: block.startMinute, end: block.endMinute, by: minutes(forPoints: translation.height))
        guard target != block.weekday || range.start != block.startMinute else { return }
        perform(.move(block.series, from: block.weekday, to: target, startMinute: range.start, endMinute: range.end))
    }

    // MARK: Drag preview

    /// A plain drag on the Mac; on iOS a press-and-hold first so dragging does not fight the scroll view.
    private func pressDrag(
        onChanged: @escaping (DragGesture.Value) -> Void,
        onEnded: @escaping (DragGesture.Value) -> Void
    ) -> AnyGesture<Void> {
        let dragGesture = DragGesture(minimumDistance: 4, coordinateSpace: .local)
        #if os(macOS)
        return AnyGesture(dragGesture.onChanged(onChanged).onEnded(onEnded).map { _ in () })
        #else
        return AnyGesture(
            LongPressGesture(minimumDuration: 0.3)
                .sequenced(before: dragGesture)
                .onChanged { value in
                    if case .second(true, let dragValue?) = value { onChanged(dragValue) }
                }
                .onEnded { value in
                    if case .second(true, let dragValue?) = value { onEnded(dragValue) } else { drag = nil }
                }
                .map { _ in () }
        )
        #endif
    }

    private func minutes(forPoints points: CGFloat) -> Int {
        Int((points / hourHeight * 60).rounded())
    }

    private func isMoving(_ block: Block) -> Bool {
        if case .moving(let moving, _) = drag { return moving.id == block.id }
        return false
    }

    /// The block's end minute, or the one a resize in progress is previewing.
    private func previewedEnd(of block: Block) -> Int {
        if case .resizing(let resizing, let delta) = drag, resizing.id == block.id {
            return TermGridMath.resized(start: block.startMinute, end: block.endMinute, by: delta)
        }
        return block.endMinute
    }

    /// The translucent block that follows a drag: the slot being drawn, or the block being moved.
    @ViewBuilder
    private func ghost(columnWidth: CGFloat, hours: ClosedRange<Int>) -> some View {
        if let drag, let ghost = ghostGeometry(for: drag, columnWidth: columnWidth) {
            let firstMinute = hours.lowerBound * 60
            let height = max(minBlockHeight, CGFloat(ghost.end - ghost.start) / 60 * hourHeight)
            VStack(alignment: .leading, spacing: 1) {
                Text(ghost.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Text(timeLabel(ghost.start, ghost.end))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .frame(width: columnWidth - 4, height: height, alignment: .topLeading)
            .background(ghost.color.opacity(0.18))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ghost.color, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .offset(
                x: gutter + CGFloat(ghost.column) * columnWidth + 2,
                y: CGFloat(ghost.start - firstMinute) / 60 * hourHeight
            )
            .allowsHitTesting(false)
        }
    }

    private struct Ghost {
        let column: Int
        let start: Int
        let end: Int
        let title: String
        let color: Color
    }

    private func ghostGeometry(for drag: Drag, columnWidth: CGFloat) -> Ghost? {
        switch drag {
        case .creating(let weekday, let anchor, let current):
            let slot = TermGridMath.slot(dragFrom: anchor, to: current)
            return Ghost(column: weekday.rawValue, start: slot.start, end: slot.end, title: "New course", color: .accentColor)
        case .moving(let block, let translation):
            let column = TermGridMath.column(from: block.weekday.rawValue, dx: translation.width, columnWidth: columnWidth, count: weekdays.count)
            let range = TermGridMath.moved(start: block.startMinute, end: block.endMinute, by: minutes(forPoints: translation.height))
            return Ghost(column: column, start: range.start, end: range.end, title: block.series.title, color: color(of: block.series))
        case .resizing:
            return nil
        }
    }

    // MARK: Labels

    private func color(of series: Series) -> Color {
        Color(hex: series.colorHex ?? series.kind.colorHex)
    }

    private func timeLabel(_ start: Int, _ end: Int) -> String {
        "\(WeekMath.timeLabel(minute: start))–\(WeekMath.timeLabel(minute: end))"
    }

    /// "Every 2 weeks · Weeks 2–14" for a course that does not run every week of the term.
    private func scheduleNote(_ series: Series) -> String? {
        var parts: [String] = []
        if series.isBiweekly { parts.append("Every 2 weeks") }
        if series.startWeek > 1 || series.endWeek < term.weekCount {
            parts.append(series.startWeek == series.endWeek ? "Week \(series.startWeek)" : "Weeks \(series.startWeek)–\(series.endWeek)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var columnSeparator: some View {
        Rectangle().fill(.quaternary).frame(width: 0.5)
    }

    // MARK: Plan

    /// One course on one weekday.
    private struct Block: Identifiable {
        let series: Series
        let weekday: Weekday
        let startMinute: Int
        let endMinute: Int
        var id: String { "\(series.uuid.uuidString)#\(weekday.rawValue)" }
    }

    private enum Drag {
        case creating(weekday: Weekday, anchorMinute: Int, currentMinute: Int)
        case moving(Block, translation: CGSize)
        case resizing(Block, minuteDelta: Int)
    }

    /// Every block by weekday, packed side by side where courses overlap.
    private struct Plan {
        var byDay: [Weekday: [Block]] = [:]
        var slots: [String: LayoutSlot] = [:]
        var items: [LayoutItem] = []

        init(series: [Series]) {
            for course in series {
                for day in course.sortedWeekdays {
                    byDay[day, default: []].append(Block(series: course, weekday: day, startMinute: course.startMinute, endMinute: course.endMinute))
                }
            }
            for list in byDay.values {
                let dayItems = list.map { LayoutItem(id: $0.id, startMinute: $0.startMinute, endMinute: $0.endMinute) }
                items += dayItems
                for slot in WeekLayout.pack(dayItems) { slots[slot.id] = slot }
            }
        }
    }
}
