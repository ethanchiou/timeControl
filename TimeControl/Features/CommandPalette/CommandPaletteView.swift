import SwiftData
import SwiftUI
import TimeControlCore

/// Spotlight-style quick-add. Host presents it; on macOS as a full-window overlay, on iOS as a sheet.
struct CommandPaletteView: View {
    @Binding var isPresented: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @State private var text = ""
    @State private var forced: CommandType?
    @State private var flash: Flash?
    @State private var flashTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    /// Replaces the preview for ~1.2s after Return. `offersTerms` adds the "Go to Terms" shortcut.
    private enum Flash: Equatable {
        case success(String)
        case failure(String, offersTerms: Bool)
    }

    /// The Mac has room for the worked example; the phone shows the short form and leans on the hints below.
    private static var prompt: String {
        #if os(macOS)
        "Add a course, event or todo… (try: CS201 Mon/Wed 10-11:30 weeks 1-14)"
        #else
        "Course, event or todo…"
        #endif
    }
    private static let examples = [
        "Interview Tue 3pm",
        "todo Finish lab report !1 tomorrow",
        "clear courses weeks 8-9"
    ]

    private var executor: CommandExecutor {
        CommandExecutor(context: modelContext, appState: appState)
    }

    private var parsed: ParsedCommand? {
        QuickAddParser.parse(text, context: executor.parserContext(), forcing: forced)
    }

    private var previewState: ParsePreview.State {
        switch flash {
        case .success(let message): return .success(message)
        case .failure(let message, _): return .error(message)
        case nil: break
        }
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return .empty }
        guard let parsed else { return .unparsed }
        switch executor.preview(parsed) {
        case .success(let info): return .ready(info)
        case .failure(let error): return .error(Self.text(for: error))
        }
    }

    private var offersTermsShortcut: Bool {
        if case .failure(_, let offers)? = flash { return offers }
        return false
    }

    var body: some View {
        #if os(macOS)
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }
                .transition(.opacity)
            card
                .frame(maxWidth: 620)
                .padding(.horizontal, 24)
                .padding(.top, 120)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { focused = true }
        .onDisappear { flashTask?.cancel() }
        #else
        NavigationStack {
            ScrollView {
                card.padding(16)
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
            }
        }
        .task {
            // A sheet's field will not take focus in the same runloop turn it is presented in.
            try? await Task.sleep(for: .milliseconds(120))
            focused = true
        }
        .onDisappear { flashTask?.cancel() }
        #endif
    }

    // MARK: Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            field
            Divider()
            #if !os(macOS)
            typePicker
            #endif
            ParsePreview(state: previewState)
            if offersTermsShortcut {
                Button("Go to Terms") {
                    appState.section = .terms
                    isPresented = false
                }
                .controlSize(.small)
            }
            hints
        }
        .padding(18)
        #if os(macOS)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator, lineWidth: 1))
        .shadow(radius: 20, y: 8)
        #endif
    }

    private var field: some View {
        TextField("", text: $text, prompt: Text(Self.prompt))
            .textFieldStyle(.plain)
            .font(.title2)
            .focused($focused)
            .onSubmit(submit)
            .onChange(of: text) { _, new in
                guard !new.isEmpty, flash != nil else { return }
                flashTask?.cancel()
                flash = nil
            }
            #if os(macOS)
            .onKeyPress(.tab) {
                cycleType()
                return .handled
            }
            .onKeyPress(.escape) {
                isPresented = false
                return .handled
            }
            #endif
    }

    #if !os(macOS)
    private var typePicker: some View {
        Picker("Type", selection: $forced) {
            Text("Auto").tag(CommandType?.none)
            ForEach(CommandType.allCases, id: \.self) { type in
                Text(type.label).tag(CommandType?.some(type))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
    #endif

    private var hints: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.examples, id: \.self) { example in
                        Button {
                            text = example
                            focused = true
                        } label: {
                            Text(example)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
            HStack {
                Text(Self.keyHints)
                Spacer(minLength: 8)
                Text(forced.map { "Forcing \($0.label.lowercased())" } ?? "Auto")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }

    private static var keyHints: String {
        #if os(macOS)
        "↩ Add · ⇥ Change type · esc Close"
        #else
        "↩ Add"
        #endif
    }

    // MARK: Actions

    private func cycleType() {
        switch forced {
        case nil: forced = .course
        case .course: forced = .event
        case .event: forced = .todo
        case .todo: forced = nil
        }
    }

    private func submit() {
        guard let parsed else { return }
        do {
            let result = try executor.execute(parsed)
            text = ""
            forced = nil
            flash = .success(result.message)
            flashTask?.cancel()
            flashTask = Task {
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                if let section = result.section {
                    appState.section = section
                    isPresented = false
                } else {
                    flash = nil
                }
            }
        } catch let error as ExecutionError {
            flash = .failure(Self.text(for: error), offersTerms: error == .noCurrentTerm)
        } catch {
            flash = .failure(error.localizedDescription, offersTerms: false)
        }
    }

    private static func text(for error: ExecutionError) -> String {
        switch error {
        case .noCurrentTerm: "No term yet — courses, blackouts and week numbers need one."
        case .invalid(let message): message
        }
    }
}

private extension CommandType {
    var label: String {
        switch self {
        case .course: "Course"
        case .event: "Event"
        case .todo: "Todo"
        }
    }
}
