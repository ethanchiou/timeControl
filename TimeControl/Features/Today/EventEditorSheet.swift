import SwiftData
import SwiftUI
import TimeControlCore

/// Create or edit a one-off event. Present as a sheet.
struct EventEditorSheet: View {
    let event: Event?
    let defaultDay: DayKey

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var groups: [SharedGroup]

    @State private var title: String
    @State private var kind: Kind
    @State private var isAllDay: Bool
    @State private var isRoutine: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var location: String
    @State private var notes: String
    /// nil = follow the kind's colour.
    @State private var colorHex: String?
    /// Group events: this member's own colour for the event; nil = follow the group's colour.
    @State private var myColorHex: String?
    /// Group events: one member finishing it finishes it for everyone.
    @State private var sharedCompletion: Bool
    /// nil = personal event.
    @State private var groupID: UUID?
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
        _colorHex = State(initialValue: event?.colorHex)
        _myColorHex = State(initialValue: event?.myColorHex)
        _sharedCompletion = State(initialValue: event?.sharedCompletion ?? false)
        _groupID = State(initialValue: event?.groupID)
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

    private var selectedGroup: SharedGroup? {
        groups.first { $0.uuid == groupID }
    }

    /// Who added this event to the group, if it's known and isn't me.
    private var authorName: String? {
        guard let event, let authorID = event.authorID, authorID != AuthService.shared.userID,
              let group = selectedGroup else { return nil }
        return group.displayName(of: authorID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, prompt: Text("Interview, exam, appointment…"))
                        .onSubmit { if canSave { save() } }
                    // The tag is optional: `.other` is "no tag" and shows no badge.
                    Picker("Tag", selection: $kind) {
                        Label("No tag", systemImage: "tag.slash").tag(Kind.other)
                        ForEach(Kind.allCases.filter { $0 != .other }) { k in
                            Label(k.displayName, systemImage: k.symbolName).tag(k)
                        }
                    }
                    Toggle("All-day", isOn: $isAllDay)
                }

                if !groups.isEmpty {
                    Section {
                        Picker("Group", selection: $groupID) {
                            Text("No group").tag(UUID?.none)
                            ForEach(groups) { group in
                                HStack {
                                    Circle()
                                        .fill(Color(hex: group.effectiveColorHex))
                                        .frame(width: 10, height: 10)
                                    Text(group.name)
                                }
                                .tag(Optional(group.uuid))
                            }
                        }
                    } header: {
                        Text("Group")
                    } footer: {
                        if let authorName {
                            Text("Added by \(authorName)")
                        }
                    }
                }

                Section {
                    if let selectedGroup {
                        // A tagged group event starts on its tag's colour (your preset for that kind, as
                        // courses do); an untagged one on the group's. Either way the pick is yours alone.
                        ColorSwatchRow(
                            selection: $myColorHex,
                            matching: nil,
                            inherited: kind != .other
                                ? (hex: KindColorSettings.hex(for: kind), symbol: kind.symbolName, label: "Match the tag")
                                : (hex: selectedGroup.effectiveColorHex, symbol: "person.2.fill", label: "Match the group")
                        )
                    } else {
                        ColorSwatchRow(selection: $colorHex, matching: kind)
                    }
                } header: {
                    Text("Color")
                } footer: {
                    if selectedGroup != nil {
                        Text(kind != .other
                            ? "Only you see this colour. Left on the tag, it follows your colour for \(kind.pluralName.lowercased()) in Settings."
                            : "Only you see this colour. Every member picks their own; leave it on the group's colour to follow whatever the group uses.")
                    }
                }

                if selectedGroup != nil {
                    Section {
                        Toggle("One completion finishes it for everyone", isOn: $sharedCompletion)
                    } header: {
                        Text("Completion")
                    } footer: {
                        Text(sharedCompletion
                            ? "A group submission: when any member marks it done, it is done for all of you."
                            : "Each member marks it done for themselves — the right default when everyone has the same assignment due.")
                    }
                }

                Section {
                    Toggle("Routine", isOn: $isRoutine)
                } footer: {
                    Text("Routine items (gym, club, standing meetings) are hidden together with courses when the eye filter is on, so only one-time items show. Anything that is not routine also gets a todo in your task list, so it counts toward the day's ring.")
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
        let saved: Event
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
            event.colorHex = colorHex
            event.groupID = groupID
            saved = event
        } else {
            let e = Event(
                title: t, kind: kind, start: start, end: end, isAllDay: isAllDay,
                location: location, notes: notes, reminderOffsetsMinutes: reminders, isRoutine: isRoutine,
                groupID: groupID
            )
            e.colorHex = colorHex
            modelContext.insert(e)
            saved = e
        }
        saved.sharedCompletion = groupID != nil && sharedCompletion
        if groupID != nil, saved.myColorHex != myColorHex {
            // The member's own colour is not part of the event row: shown at once, saved to its own
            // table, and left out of the outbox.
            let context = modelContext
            SyncTracker.shared.applyingRemote(in: context) { saved.myColorHex = myColorHex }
            Task { try? await GroupService.shared.setEventColor(myColorHex, for: saved, in: context) }
        }
        dismiss()
    }
}
