import SwiftData
import SwiftUI
import TimeControlCore

/// "Clear courses for weeks 8–9": creates or edits a reversible Blackout inside `term`. Present as a sheet.
struct BlackoutEditorSheet: View {
    let term: Term
    let blackout: Blackout?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var everything: Bool
    @State private var kinds: Set<Kind>
    @State private var startWeek: Int
    @State private var endWeek: Int
    @State private var reason: String

    init(term: Term, blackout: Blackout? = nil, initialKinds: Set<Kind> = [.course], initialWeeks: ClosedRange<Int>? = nil) {
        self.term = term
        self.blackout = blackout
        let k = blackout?.kinds ?? initialKinds
        _everything = State(initialValue: k.isEmpty)
        _kinds = State(initialValue: k.isEmpty ? [.course] : k)
        let weeks = blackout.flatMap { b -> ClosedRange<Int>? in
            guard let a = term.weekNumber(of: b.start), let z = term.weekNumber(of: b.end) else { return nil }
            return a...z
        } ?? initialWeeks ?? {
            let w = term.weekNumber(of: .today()) ?? 1
            return w...w
        }()
        _startWeek = State(initialValue: weeks.lowerBound)
        _endWeek = State(initialValue: weeks.upperBound)
        _reason = State(initialValue: blackout?.reason ?? "")
    }

    private var isEditing: Bool { blackout != nil }
    private var canSave: Bool { endWeek >= startWeek && (everything || !kinds.isEmpty) }
    private var days: ClosedRange<DayKey> { term.weeks.days(inWeeks: min(startWeek, endWeek)...max(startWeek, endWeek)) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Hide") {
                    Toggle("Everything recurring", isOn: $everything)
                    if !everything {
                        ForEach(Kind.allCases) { k in
                            Toggle(isOn: Binding(
                                get: { kinds.contains(k) },
                                set: { on in if on { kinds.insert(k) } else { kinds.remove(k) } }
                            )) {
                                Label(k.pluralName, systemImage: k.symbolName)
                            }
                        }
                    }
                }

                Section("Weeks") {
                    Picker("From week", selection: $startWeek) {
                        ForEach(1...term.weekCount, id: \.self) { Text("Week \($0)").tag($0) }
                    }
                    Picker("To week", selection: $endWeek) {
                        ForEach(1...term.weekCount, id: \.self) { Text("Week \($0)").tag($0) }
                    }
                    Text("\(days.lowerBound.startDate().formatted(date: .abbreviated, time: .omitted)) – \(days.upperBound.startDate().formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Reason") {
                    TextField("Reason", text: $reason, prompt: Text("Exam period"))
                }

                Section {
                    Text("Nothing is deleted. Remove this blackout later to bring everything back.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isEditing {
                    Section {
                        Button("Remove Blackout", role: .destructive) {
                            if let blackout { modelContext.delete(blackout) }
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Blackout" : "Clear Weeks")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Clear") { save() }.disabled(!canSave)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #else
        .presentationDetents([.large])
        #endif
    }

    private func save() {
        let selected: Set<Kind> = everything ? [] : kinds
        if let blackout {
            blackout.start = days.lowerBound
            blackout.end = days.upperBound
            blackout.kinds = selected
            blackout.reason = reason
        } else {
            let b = Blackout(start: days.lowerBound, end: days.upperBound, kinds: selected, reason: reason, term: term)
            modelContext.insert(b)
        }
        dismiss()
    }
}
