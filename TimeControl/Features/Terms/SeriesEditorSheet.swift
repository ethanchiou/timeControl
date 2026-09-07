import SwiftData
import SwiftUI
import TimeControlCore

/// Create or edit a recurring course inside `term`. Present as a sheet.
struct SeriesEditorSheet: View {
    let term: Term
    let series: Series?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var kind: Kind
    @State private var weekdays: Set<Weekday>
    @State private var start: Date
    @State private var end: Date
    @State private var intervalWeeks: Int
    @State private var startWeek: Int
    @State private var endWeek: Int
    @State private var location: String
    @State private var notes: String
    /// nil = follow the kind's colour.
    @State private var colorHex: String?
    @State private var confirmDelete = false

    /// `template` is the course a new time slot belongs to: its title, kind, location, notes and weeks are
    /// copied so the second slot of CS201 is CS201 without retyping anything.
    init(
        term: Term,
        series: Series? = nil,
        initialWeekdays: Set<Weekday> = [],
        initialStartMinute: Int = 600,
        initialEndMinute: Int? = nil,
        template: Series? = nil
    ) {
        self.term = term
        self.series = series
        let details = series ?? template
        _title = State(initialValue: details?.title ?? "")
        _kind = State(initialValue: details?.kind ?? .course)
        _weekdays = State(initialValue: series?.weekdays ?? initialWeekdays)
        _start = State(initialValue: Self.date(minute: series?.startMinute ?? initialStartMinute))
        _end = State(initialValue: Self.date(minute: series?.endMinute ?? initialEndMinute ?? initialStartMinute + 90))
        _intervalWeeks = State(initialValue: details?.intervalWeeks ?? 1)
        _startWeek = State(initialValue: details?.startWeek ?? 1)
        _endWeek = State(initialValue: details?.endWeek ?? term.weekCount)
        _location = State(initialValue: details?.location ?? "")
        _notes = State(initialValue: details?.notes ?? "")
        _colorHex = State(initialValue: details?.colorHex)
    }

    private var isEditing: Bool { series != nil }
    private var startMinute: Int { WeekMath.minuteOfDay(start) }
    private var endMinute: Int { WeekMath.minuteOfDay(end) }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !weekdays.isEmpty && endMinute > startMinute && endWeek >= startWeek
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, prompt: Text("CS201 Data Structures"))
                        .onSubmit { if canSave { save() } }
                    Picker("Kind", selection: $kind) {
                        ForEach(Kind.allCases) { k in
                            Label(k.displayName, systemImage: k.symbolName).tag(k)
                        }
                    }
                    TextField("Location", text: $location, prompt: Text("Room 204"))
                    if !isEditing, !existingTitles.isEmpty {
                        Menu {
                            ForEach(existingTitles, id: \.self) { existing in
                                Button(existing) { copyDetails(fromCourseTitled: existing) }
                            }
                        } label: {
                            Label("Same Course As…", systemImage: "doc.on.doc")
                        }
                    }
                }

                Section("Days") {
                    WeekdayChips(selection: $weekdays)
                }

                Section("Color") {
                    ColorSwatchRow(selection: $colorHex, matching: kind)
                }

                Section("Time") {
                    DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
                    if endMinute <= startMinute {
                        Text("End must be after start").foregroundStyle(.red).font(.caption)
                    }
                }

                Section("Repeats") {
                    Picker("Every", selection: $intervalWeeks) {
                        Text("Week").tag(1)
                        Text("Two weeks").tag(2)
                    }
                    .pickerStyle(.segmented)
                    Picker("From week", selection: $startWeek) {
                        ForEach(1...term.weekCount, id: \.self) { Text("Week \($0)").tag($0) }
                    }
                    Picker("To week", selection: $endWeek) {
                        ForEach(1...term.weekCount, id: \.self) { Text("Week \($0)").tag($0) }
                    }
                    Text(scheduleSummary).font(.caption).foregroundStyle(.secondary)
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if isEditing {
                    Section {
                        Button("Delete Course", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Course" : "New Course")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }.keyboardShortcut(.defaultAction).disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this course and all its occurrences?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let series { modelContext.delete(series) }
                    dismiss()
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #else
        .presentationDetents([.large])
        #endif
    }

    /// Distinct titles already in the term, so another time slot can join a course by name.
    private var existingTitles: [String] {
        var seen: Set<String> = []
        return term.sortedSeries.map(\.title).filter { seen.insert($0).inserted }
    }

    private func copyDetails(fromCourseTitled existing: String) {
        guard let source = term.sortedSeries.first(where: { $0.title == existing }) else { return }
        title = source.title
        kind = source.kind
        location = source.location
        notes = source.notes
        intervalWeeks = source.intervalWeeks
        startWeek = source.startWeek
        endWeek = source.endWeek
        colorHex = source.colorHex
    }

    private var scheduleSummary: String {
        let days = weekdays.sorted().map(\.shortName).joined(separator: "/")
        let every = intervalWeeks == 2 ? "every other week" : "weekly"
        let weeks = startWeek == endWeek ? "week \(startWeek)" : "weeks \(startWeek)–\(endWeek)"
        return "\(days.isEmpty ? "No days" : days), \(every), \(weeks) of \(term.name)"
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespaces)
        if let series {
            series.title = t
            series.kind = kind
            series.weekdays = weekdays
            series.startMinute = startMinute
            series.endMinute = endMinute
            series.intervalWeeks = intervalWeeks
            series.startWeek = startWeek
            series.endWeek = endWeek
            series.location = location
            series.notes = notes
            series.colorHex = colorHex
        } else {
            let s = Series(
                title: t, kind: kind, weekdays: weekdays, startMinute: startMinute, endMinute: endMinute,
                intervalWeeks: intervalWeeks, startWeek: startWeek, endWeek: endWeek, location: location, notes: notes
            )
            s.colorHex = colorHex
            modelContext.insert(s)
            s.term = term
        }
        dismiss()
    }

    private static func date(minute: Int) -> Date {
        WeekMath.instant(day: .today(), minute: minute)
    }
}

/// Seven toggle chips, Monday first.
struct WeekdayChips: View {
    @Binding var selection: Set<Weekday>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(day.shortName)
                        .font(.callout.weight(on ? .semibold : .regular))
                        .frame(minWidth: 40)
                        .padding(.vertical, 6)
                        // Touch needs 44pt; the Mac keeps the tighter chip it was designed with.
                        #if !os(macOS)
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                        #endif
                        .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
