import SwiftData
import SwiftUI
import TimeControlCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Wraps exported backup JSON so it can be handed to `.fileExporter`.
struct BackupFileDocument: FileDocument {
    nonisolated static var readableContentTypes: [UTType] { [.json] }
    nonisolated static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    nonisolated init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    nonisolated func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// The "Backup" section of Settings: export the whole store as JSON, or import one back in.
struct BackupSection: View {
    @Environment(\.modelContext) private var modelContext

    @State private var isExporting = false
    @State private var exportDocument: BackupFileDocument?
    @State private var isImporting = false
    @State private var pendingImportURL: URL?
    @State private var confirmImportMode = false
    @State private var importSummaryText: String?
    @State private var errorMessage: String?
    @State private var autoBackupEnabled = AutoBackupService.isEnabled
    @State private var autoBackupCount = 0

    var body: some View {
        Section {
            Toggle("Daily automatic backup", isOn: $autoBackupEnabled)
                .onChange(of: autoBackupEnabled) { _, newValue in
                    AutoBackupService.isEnabled = newValue
                }
            if autoBackupEnabled {
                LabeledContent("Last backup", value: lastAutoBackupText)
                #if os(macOS)
                Button("Show Backups in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(AutoBackupService.existingBackups())
                }
                .disabled(autoBackupCount == 0)
                #endif
            }
            Button("Export Backup…") { beginExport() }
            Button("Import Backup…") { isImporting = true }
            if let importSummaryText {
                Text(importSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("JSON backup of terms, courses, blackouts, events, projects and todos. Automatic backups keep the last \(AutoBackupService.keepCount) days inside the app, which does not survive deleting the app or losing the device — export somewhere else for that.")
        }
        .onAppear { autoBackupCount = AutoBackupService.existingBackups().count }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: BackupService.suggestedFilename()
        ) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                pendingImportURL = url
                confirmImportMode = true
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog("Import Backup", isPresented: $confirmImportMode, titleVisibility: .visible) {
            Button("Replace Everything", role: .destructive) { performImport(mode: .replace) }
            Button("Merge") { performImport(mode: .merge) }
            Button("Cancel", role: .cancel) { pendingImportURL = nil }
        }
        .alert("Backup Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// "Today", "Yesterday", or the date; "Never" before the first one has run.
    private var lastAutoBackupText: String {
        guard let day = AutoBackupService.lastRunDay else { return "Never" }
        switch day - DayKey.today() {
        case 0: return "Today"
        case -1: return "Yesterday"
        default: return day.startDate().formatted(.dateTime.month(.abbreviated).day().year())
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func beginExport() {
        do {
            let data = try BackupService.exportData(from: modelContext)
            exportDocument = BackupFileDocument(data: data)
            isExporting = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performImport(mode: BackupImportMode) {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let summary = try BackupService.importData(data, into: modelContext, mode: mode)
            importSummaryText = "Imported: \(summary.inserted) inserted, \(summary.updated) updated"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
