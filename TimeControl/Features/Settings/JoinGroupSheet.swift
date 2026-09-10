import SwiftData
import SwiftUI

/// Join a group with the eight-character code one of its members shared. Present as a sheet.
struct JoinGroupSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @FocusState private var codeFieldFocused: Bool

    private var canJoin: Bool { code.count == 8 && !isBusy }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Join code", text: $code, prompt: Text("ABCD2345"))
                        .textContentType(.oneTimeCode)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                        .focused($codeFieldFocused)
                        .onChange(of: code) { _, newValue in
                            // Codes get pasted with the spaces and dashes people add when they retype them.
                            let cleaned = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(8))
                            if cleaned != newValue { code = cleaned }
                        }
                        .onSubmit { if canJoin { join() } }
                } footer: {
                    Text("Eight letters and digits, from a member of the group. Spaces and dashes are ignored.")
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
            .navigationTitle("Join Group")
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
                        Button("Join") { join() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(!canJoin)
                    }
                }
            }
            .onAppear { codeFieldFocused = true }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 260)
        #else
        .presentationDetents([.medium])
        #endif
    }

    private func join() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                _ = try await GroupService.shared.join(code: code, into: modelContext)
                dismiss()
            } catch {
                errorMessage = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
            }
        }
    }
}
