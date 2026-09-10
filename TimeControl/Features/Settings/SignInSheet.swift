import SwiftUI

/// Sign in with an email address and the six-digit code that lands in the inbox. Present as a sheet.
///
/// Both steps live in the one sheet: the address, then the code. The same email carries a link that
/// opens the app and signs in on its own, so the code step tells people either will do.
struct SignInSheet: View {
    @Environment(\.dismiss) private var dismiss

    private enum Step { case email, code }
    private enum Field { case email, code }

    @State private var step: Step = .email
    @State private var email = ""
    @State private var code = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private var auth: AuthService { .shared }

    private var canSendCode: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") && !trimmed.hasPrefix("@") && !trimmed.hasSuffix("@")
    }

    private var canVerify: Bool { code.count == 6 }

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .email: emailSection
                case .code: codeSection
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
            .navigationTitle("Sign In")
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
                        switch step {
                        case .email:
                            Button("Send Code") { sendCode() }
                                .keyboardShortcut(.defaultAction)
                                .disabled(!canSendCode)
                        case .code:
                            Button("Sign In") { verify() }
                                .keyboardShortcut(.defaultAction)
                                .disabled(!canVerify)
                        }
                    }
                }
            }
            .onAppear { focus = .email }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 300)
        #else
        .presentationDetents([.medium])
        #endif
    }

    private var emailSection: some View {
        Section {
            TextField("Email", text: $email, prompt: Text("you@example.com"))
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .focused($focus, equals: .email)
                .onSubmit { if canSendCode { sendCode() } }
        } footer: {
            Text("We email a six-digit code and a sign-in link; both last ten minutes. There is no password to remember, and a new address becomes an account.")
        }
    }

    private var codeSection: some View {
        Section {
            TextField("Code", text: $code, prompt: Text("123456"))
                .textContentType(.oneTimeCode)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .focused($focus, equals: .code)
                .onChange(of: code) { _, newValue in
                    // Strip first and let the edit settle, so a pasted "123 456" auto-submits once.
                    let digits = String(newValue.filter(\.isNumber).prefix(6))
                    guard digits == newValue else {
                        code = digits
                        return
                    }
                    if digits.count == 6 { verify() }
                }
                .onSubmit { if canVerify { verify() } }
            Button("Resend code") { sendCode() }
                .disabled(isBusy)
            Button("Use a different address") {
                step = .email
                code = ""
                errorMessage = nil
                focus = .email
            }
        } footer: {
            Text("Enter the code from the email, or tap the link in it. We sent it to \(email.trimmingCharacters(in: .whitespacesAndNewlines)).")
        }
    }

    private func sendCode() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await auth.sendCode(to: email)
                errorMessage = nil
                code = ""
                step = .code
                focus = .code
            } catch {
                errorMessage = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
            }
        }
    }

    private func verify() {
        guard !isBusy, canVerify else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await auth.verify(email: email, code: code)
                dismiss()
            } catch {
                errorMessage = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
                code = ""
                focus = .code
            }
        }
    }
}
