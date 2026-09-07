import SwiftData
import SwiftUI
import TimeControlCore

/// Create or edit a term. Present as a sheet.
struct TermEditorSheet: View {
    let term: Term?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var startDate: Date
    @State private var endDate: Date

    init(term: Term?) {
        self.term = term
        _name = State(initialValue: term?.name ?? Self.suggestedName(for: .today()))
        _startDate = State(initialValue: term?.start.startDate() ?? DayKey.today().startDate())
        _endDate = State(initialValue: term?.end.startDate() ?? (DayKey.today() + 104).startDate())  // 15 weeks
    }

    private var isEditing: Bool { term != nil }
    private var startDayKey: DayKey { DayKey(startDate) }
    private var endDayKey: DayKey { DayKey(endDate) }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && endDayKey >= startDayKey
    }

    private var weeksCaption: String {
        let weeks = TermWeeks(termStart: startDayKey, termEnd: endDayKey)
        let firstWeek = weeks.firstWeekStart.startDate().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(weeks.weekCount) week\(weeks.weekCount == 1 ? "" : "s") · week 1 starts \(firstWeek)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Fall 2026"))
                        .onSubmit { if canSave { save() } }
                    DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    DatePicker("Ends", selection: $endDate, displayedComponents: .date)
                    if endDayKey < startDayKey {
                        Text("End must be on or after start").foregroundStyle(.red).font(.caption)
                    } else {
                        Text(weeksCaption).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Term" : "New Term")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    // The default action, so Return adds and the button reads as the one to press.
                    Button(isEditing ? "Save" : "Add") { save() }.keyboardShortcut(.defaultAction).disabled(!canSave)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #else
        .presentationDetents([.large])
        #endif
    }

    /// "Fall 2026" for a term starting in September: a name to keep or retype, so a new term can be added
    /// straight away instead of sitting behind a disabled button that looks no different from an enabled one.
    private static func suggestedName(for day: DayKey) -> String {
        let civil = day.civil
        let season = switch civil.month {
        case 1...4: "Spring"
        case 5...7: "Summer"
        default: "Fall"
        }
        return "\(season) \(civil.year)"
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        if let term {
            term.name = n
            term.start = startDayKey
            term.end = endDayKey
        } else {
            let t = Term(name: n, start: startDayKey, end: endDayKey)
            modelContext.insert(t)
        }
        dismiss()
    }
}
