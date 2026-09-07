import SwiftData
import SwiftUI
import TimeControlCore

/// Create or edit a one-off event. Present as a sheet.
struct EventEditorSheet: View {
    let event: Event?
    let defaultDay: DayKey

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var kind: Kind
    @State private var isAllDay: Bool
    @State private var isRoutine: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var location: String
    @State private var notes: String
    @State private var reminderMinutes: Set<Int>
    @State private var remindersEdited: Bool
    @State private var confirmDelete = false

    /// (toggle title, minutes before start) pairs, in display order.
    private static let reminderOptions: [(title: String, minutes: Int)] = [
        ("At time", 0),
        ("10 minutes before", 10),
        ("30 minutes before", 30),
        ("1 hour before", 60),
        ("1 day before", 1440),
    ]

    init(event: Event? = nil, defaultDay: DayKey = .today()) {
        self.event = event
        self.defaultDay = defaultDay
        let initialKind = event?.kind ?? .other
        _title = State(initialValue: event?.title ?? "")
        _kind = State(initialValue: initialKind)
        _isAllDay = State(initialValue: event?.isAllDay ?? false)
        _isRoutine = State(initialValue: event?.isRoutine ?? false)
        let defaultStart = WeekMath.instant(day: defaultDay, minute: 9 * 60)
        _start = State(initialValue: event?.startDate ?? defaultStart)
        _end = State(initialValue: event?.endDate ?? defaultStart.addingTimeInterval(3600))
        _location = State(initialValue: event?.location ?? "")
        _notes = State(initialValue: event?.notes ?? "")
        if let event {
            _reminderMinutes = State(initialValue: Set(event.reminderOffsetsMinutes))
            _remindersEdited = State(initialValue: true)
        } else {
            _reminderMinutes = State(initialValue: Set(initialKind.defaultReminderMinutes.map { [$0] } ?? []))
            _remindersEdited = State(initialValue: false)
        }
    }

    private var isEditing: Bool { event != nil }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }
    private var dateComponents: DatePickerComponents { isAllDay ? [.date] : [.date, .hourAndMinute] }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, prompt: Text("Interview, exam, appointment…"))
                        .onSubmit { if canSave { save() } }
                    Picker("Kind", selection: $kind) {
                        ForEach(Kind.allCases) { k in
                            Label(k.displayName, systemImage: k.symbolName).tag(k)
                        }
                    }
                    Toggle("All-day", isOn: $isAllDay)
                }

                Section {
                    Toggle("Routine", isOn: $isRoutine)
                } footer: {
                    Text("Routine items (gym, club, standing meetings) are hidden together with courses when the eye filter is on, so only one-time items show.")
                }

                Section {
                    DatePicker("Starts", selection: $start, displayedComponents: dateComponents)
                        .onChange(of: start) { _, newStart in
                            if end < newStart { end = newStart.addingTimeInterval(3600) }
                        }
                    DatePicker("Ends", selection: $end, displayedComponents: dateComponents)
                    TextField("Location", text: $location, prompt: Text("Room, building, link…"))
                }

                Section("Reminders") {
                    ForEach(Self.reminderOptions, id: \.minutes) { option in
                        Toggle(option.title, isOn: reminderBinding(for: option.minutes))
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if isEditing {
                    Section {
                        Button("Delete Event", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Event" : "New Event")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }.keyboardShortcut(.defaultAction).disabled(!canSave)
                }
            }
            .onChange(of: kind) { _, newKind in
                guard !isEditing, !remindersEdited else { return }
                reminderMinutes = Set(newKind.defaultReminderMinutes.map { [$0] } ?? [])
            }
            .confirmationDialog("Delete this event?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let event { modelContext.delete(event) }
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

    private func reminderBinding(for minutes: Int) -> Binding<Bool> {
        Binding(
            get: { reminderMinutes.contains(minutes) },
            set: { isOn in
                remindersEdited = true
                if isOn { reminderMinutes.insert(minutes) } else { reminderMinutes.remove(minutes) }
            }
        )
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespaces)
        let reminders = Self.reminderOptions.map(\.minutes).filter { reminderMinutes.contains($0) }
        if let event {
            event.title = t
            event.kind = kind
            event.startDate = start
            event.endDate = max(end, start)
            event.isAllDay = isAllDay
            event.location = location
            event.notes = notes
            event.reminderOffsetsMinutes = reminders
            event.isRoutine = isRoutine
        } else {
            let e = Event(
                title: t, kind: kind, start: start, end: end, isAllDay: isAllDay,
                location: location, notes: notes, reminderOffsetsMinutes: reminders, isRoutine: isRoutine
            )
            modelContext.insert(e)
        }
        dismiss()
    }
}
