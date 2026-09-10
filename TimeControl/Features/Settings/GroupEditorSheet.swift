import SwiftData
import SwiftUI

/// Create a group, or rename and recolour one. Present as a sheet.
///
/// The colour here is the group's own, which every member sees unless they override it; a group has no
/// `Kind` to inherit from, so the palette has no "match" swatch and one colour is always chosen.
struct GroupEditorSheet: View {
    let group: SharedGroup?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var colorHex: String?
    @State private var isBusy = false
    @State private var errorMessage: String?

    init(group: SharedGroup? = nil) {
        self.group = group
        _name = State(initialValue: group?.name ?? "")
        _colorHex = State(initialValue: group?.colorHex ?? ColorSwatchRow.palette[0])
    }

    private var isEditing: Bool { group != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !isBusy }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Study group, flatmates, band…"))
                        .onSubmit { if canSave { save() } }
                }

                Section("Color") {
                    ColorSwatchRow(selection: $colorHex, matching: nil)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Group" : "New Group")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
                ToolbarItem(placement: .confirmationAction) {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(isEditing ? "Save" : "Create") { save() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(!canSave)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #else
        .presentationDetents([.medium])
        #endif
    }

    private func save() {
        guard !isBusy else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = colorHex ?? ColorSwatchRow.palette[0]
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                if let group {
                    try await GroupService.shared.update(group, name: trimmed, colorHex: hex, in: modelContext)
                } else {
                    _ = try await GroupService.shared.create(name: trimmed, colorHex: hex, into: modelContext)
                }
                dismiss()
            } catch {
                errorMessage = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
            }
        }
    }
}
