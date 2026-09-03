import SwiftUI
import TimeControlCore

/// What a block asks the week to do. `WeekView` owns every sheet, dialog and model edit, so a block
/// never touches the model context and popovers never fight with sheets.
enum WeekAction {
    /// iOS only: macOS shows the details card in a popover anchored to the block.
    case showDetails(Occurrence)
    case skip(Occurrence)
    case editSeries(Occurrence)
    case editEvent(Occurrence)
    case hideKindThisWeek(Occurrence)
    case delete(Occurrence)
    case restore(Occurrence)
}

/// One occurrence drawn in a day column. The caller sizes it; the contents adapt to the height.
struct OccurrenceBlock: View {
    let occurrence: Occurrence
    let height: CGFloat
    let weeks: TermWeeks?
    let perform: @MainActor (WeekAction) -> Void

    @State private var showsDetails = false

    var body: some View {
        #if os(macOS)
        block.popover(isPresented: $showsDetails, arrowEdge: .trailing) {
            OccurrenceDetailsCard(occurrence: occurrence, weeks: weeks, perform: perform)
        }
        #else
        block
        #endif
    }

    private var block: some View {
        Button(action: open) { content }
            .buttonStyle(.plain)
            .contextMenu {
                OccurrenceActions(occurrence: occurrence, weeks: weeks, perform: perform)
            }
    }

    private func open() {
        #if os(macOS)
        showsDetails = true
        #else
        perform(.showDetails(occurrence))
        #endif
    }

    // MARK: Contents

    private var color: Color { Color(hex: occurrence.colorHex) }
    private var isSuppressed: Bool { occurrence.isSuppressed }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 6) }

    private var timeRange: String {
        let start = WeekMath.minuteOfDay(occurrence.start)
        let end = WeekMath.minuteOfDay(occurrence.end)
        return "\(WeekMath.timeLabel(minute: start))–\(WeekMath.timeLabel(minute: end))"
    }

    private var content: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(occurrence.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(height > 40 ? 2 : 1)
                    .strikethrough(isSuppressed)
                if !occurrence.isAllDay, height > 40 {
                    Text(timeRange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if height > 60, !occurrence.location.isEmpty {
                    Text(occurrence.location)
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
        .overlay {
            if isSuppressed {
                shape.strokeBorder(color, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .clipShape(shape)
        .contentShape(shape)
        .opacity(isSuppressed ? 0.4 : 1)
        .help(isSuppressed ? "Hidden by blackout" : helpText)
    }

    private var helpText: String {
        let where_ = occurrence.location.isEmpty ? "" : " · \(occurrence.location)"
        if occurrence.isAllDay { return "\(occurrence.title) · All day\(where_)" }
        return "\(occurrence.title) · \(timeRange)\(where_)"
    }
}

/// The buttons an occurrence offers, identical in the context menu and in the details card.
struct OccurrenceActions: View {
    let occurrence: Occurrence
    let weeks: TermWeeks?
    let perform: @MainActor (WeekAction) -> Void

    private var canBlackout: Bool { weeks?.weekNumber(of: occurrence.day) != nil }

    var body: some View {
        if occurrence.seriesID != nil {
            if occurrence.isSuppressed {
                Button {
                    perform(.restore(occurrence))
                } label: {
                    Label("Restore (Remove Blackout)…", systemImage: "arrow.uturn.backward")
                }
            } else {
                Button {
                    perform(.skip(occurrence))
                } label: {
                    Label("Skip This Occurrence", systemImage: "calendar.badge.minus")
                }
                Button {
                    perform(.editSeries(occurrence))
                } label: {
                    Label("Edit \(occurrence.kind.displayName)…", systemImage: "pencil")
                }
                if canBlackout {
                    Button {
                        perform(.hideKindThisWeek(occurrence))
                    } label: {
                        Label("Hide \(occurrence.kind.pluralName) This Week…", systemImage: "eye.slash")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    perform(.delete(occurrence))
                } label: {
                    Label("Delete \(occurrence.kind.displayName)…", systemImage: "trash")
                }
            }
        } else {
            Button {
                perform(.editEvent(occurrence))
            } label: {
                Label("Edit Event…", systemImage: "pencil")
            }
            Button(role: .destructive) {
                perform(.delete(occurrence))
            } label: {
                Label("Delete Event…", systemImage: "trash")
            }
        }
    }
}

/// Details for one occurrence: a popover on macOS, a sheet on iOS.
struct OccurrenceDetailsCard: View {
    let occurrence: Occurrence
    let weeks: TermWeeks?
    let perform: @MainActor (WeekAction) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        card.frame(width: 260, alignment: .leading)
        #else
        card.frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: occurrence.kind.symbolName)
                Text(occurrence.kind.displayName.uppercased())
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color(hex: occurrence.colorHex))

            Text(occurrence.title)
                .font(.headline)

            Text(whenLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !occurrence.location.isEmpty {
                Label(occurrence.location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let weekLine {
                Text(weekLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if occurrence.isSuppressed {
                Label("Hidden by blackout", systemImage: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider().padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 8) {
                OccurrenceActions(occurrence: occurrence, weeks: weeks, perform: run)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }

    /// Close this popover/sheet before the week puts up an editor or a confirmation.
    private func run(_ action: WeekAction) {
        dismiss()
        perform(action)
    }

    /// "Mon, Sep 7 · 10:00–11:30".
    private var whenLine: String {
        let date = occurrence.day.startDate().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        if occurrence.isAllDay { return "\(date) · All day" }
        let start = WeekMath.minuteOfDay(occurrence.start)
        let end = WeekMath.minuteOfDay(occurrence.end)
        return "\(date) · \(WeekMath.timeLabel(minute: start))–\(WeekMath.timeLabel(minute: end))"
    }

    private var weekLine: String? {
        guard let weeks, let number = weeks.weekNumber(of: occurrence.day) else { return nil }
        return "Week \(number) of \(weeks.weekCount)"
    }
}
