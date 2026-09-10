import SwiftData
import SwiftUI
import TimeControlCore

/// Agenda list for a single day: all-day pills, then timed rows with a "now" line for today.
struct DayTimeline: View {
    let day: DayKey
    let occurrences: [Occurrence]
    let term: Term?
    var onEditEvent: (Event) -> Void
    var onEditSeries: (Series) -> Void
    /// When false, renders its rows directly with no internal `ScrollView` — for embedding in a caller's own scroll view.
    var scrollsInternally: Bool = true

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @State private var selectedOccurrence: Occurrence?
    @State private var pendingDeleteOccurrence: Occurrence?

    private var isToday: Bool { day == .today() }

    private var allDayOccurrences: [Occurrence] {
        occurrences.filter(\.isAllDay).sorted { $0.title < $1.title }
    }

    private var timedOccurrences: [Occurrence] {
        occurrences.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
    }

    private enum Row: Identifiable {
        case now
        case occurrence(Occurrence)

        var id: String {
            switch self {
            case .now: "now-line"
            case .occurrence(let occurrence): occurrence.id
            }
        }
    }

    private func rows(at now: Date) -> [Row] {
        var result = timedOccurrences.map(Row.occurrence)
        guard isToday, !timedOccurrences.isEmpty else { return result }
        let index = timedOccurrences.firstIndex { $0.start > now } ?? timedOccurrences.count
        result.insert(.now, at: index)
        return result
    }

    var body: some View {
        Group {
            if occurrences.isEmpty {
                emptyState
            } else {
                TimelineView(.everyMinute) { context in
                    if scrollsInternally {
                        ScrollView {
                            timelineContent(at: context.date)
                        }
                    } else {
                        timelineContent(at: context.date)
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete this event?",
            isPresented: Binding(
                get: { pendingDeleteOccurrence != nil },
                set: { if !$0 { pendingDeleteOccurrence = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let occurrence = pendingDeleteOccurrence {
                    modelContext.deleteSource(of: occurrence)
                }
                pendingDeleteOccurrence = nil
            }
        }
    }

    @ViewBuilder
    private func timelineContent(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !allDayOccurrences.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(allDayOccurrences) { occurrence in
                        allDayPill(occurrence)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            ForEach(rows(at: now)) { row in
                switch row {
                case .now: nowLine(at: now)
                case .occurrence(let occurrence): timedRow(occurrence)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            EmptyStateIllustration(.today, size: 72)
            Text("Nothing scheduled")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Rows

    @ViewBuilder
    private func allDayPill(_ occurrence: Occurrence) -> some View {
        withInteractions(occurrence) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: occurrence.colorHex))
                    .frame(width: 6, height: 6)
                if occurrence.isGroup {
                    GroupGlyph(colorHex: occurrence.colorHex)
                        .font(.caption2)
                }
                Text(occurrence.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(hex: occurrence.colorHex).opacity(0.12), in: Capsule())
        }
    }

    @ViewBuilder
    private func timedRow(_ occurrence: Occurrence) -> some View {
        withInteractions(occurrence) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(WeekMath.timeLabel(minute: WeekMath.minuteOfDay(occurrence.start)))
                    Text(WeekMath.timeLabel(minute: WeekMath.minuteOfDay(occurrence.end)))
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)

                Rectangle()
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
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func nowLine(at date: Date) -> some View {
        HStack(spacing: 8) {
            Text(date.formatted(.dateTime.hour().minute()))
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.red)
                .frame(width: 64, alignment: .leading)
            Rectangle()
                .fill(Color.red)
                .frame(height: 1)
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
    }

    // MARK: Interactions

    @ViewBuilder
    private func withInteractions<Content: View>(_ occurrence: Occurrence, @ViewBuilder content: () -> Content) -> some View {
        content()
            .contentShape(Rectangle())
            .onTapGesture { selectedOccurrence = occurrence }
            .contextMenu { actionButtons(for: occurrence) }
            #if os(macOS)
            .popover(isPresented: popoverBinding(for: occurrence), arrowEdge: .trailing) {
                detailContent(for: occurrence)
            }
            #else
            .sheet(isPresented: popoverBinding(for: occurrence)) {
                detailSheet(for: occurrence)
            }
            #endif
    }

    private func popoverBinding(for occurrence: Occurrence) -> Binding<Bool> {
        Binding(
            get: { selectedOccurrence?.id == occurrence.id },
            set: { isPresented in if !isPresented { selectedOccurrence = nil } }
        )
    }

    @ViewBuilder
    private func detailContent(for occurrence: Occurrence) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(occurrence.title).font(.headline)
                if !occurrence.isAllDay {
                    Text("\(WeekMath.timeLabel(minute: WeekMath.minuteOfDay(occurrence.start))) – \(WeekMath.timeLabel(minute: WeekMath.minuteOfDay(occurrence.end)))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !occurrence.location.isEmpty {
                    Label(occurrence.location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                KindBadge(kind: occurrence.kind, style: .pill)
                if let group = group(for: occurrence) {
                    HStack(spacing: 6) {
                        GroupChip(name: group.name, colorHex: group.effectiveColorHex)
                        if let name = authorName(for: occurrence, group: group) {
                            Text("Added by \(name)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                actionButtons(for: occurrence)
            }
        }
        .padding()
        .frame(minWidth: 240)
    }

    @ViewBuilder
    private func detailSheet(for occurrence: Occurrence) -> some View {
        NavigationStack {
            detailContent(for: occurrence)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { selectedOccurrence = nil }
                    }
                }
        }
    }

    /// The shared group an occurrence belongs to, or nil if it isn't a group event or the group
    /// isn't in the local store (not yet synced).
    private func group(for occurrence: Occurrence) -> SharedGroup? {
        guard let groupID = occurrence.groupID else { return nil }
        return modelContext.group(uuid: groupID)
    }

    private func authorName(for occurrence: Occurrence, group: SharedGroup) -> String? {
        guard let eventID = occurrence.eventID,
              let event = modelContext.event(uuid: eventID), let authorID = event.authorID else { return nil }
        return group.displayName(of: authorID)
    }

    @ViewBuilder
    private func actionButtons(for occurrence: Occurrence) -> some View {
        switch occurrence.source {
        case .event(let id):
            Button("Edit Event…") {
                if let event = modelContext.event(uuid: id) { onEditEvent(event) }
                selectedOccurrence = nil
            }
            Button("Delete Event…", role: .destructive) {
                pendingDeleteOccurrence = occurrence
                selectedOccurrence = nil
            }
        case .series(let seriesID, let occurrenceDay):
                Button("Skip This Occurrence") {
                    modelContext.skip(seriesID: seriesID, on: occurrenceDay)
                    selectedOccurrence = nil
                }
                Button("Edit Course…") {
                    if let series = modelContext.series(uuid: seriesID), series.term != nil {
                        onEditSeries(series)
                    }
                    selectedOccurrence = nil
                }
        }
    }
}
