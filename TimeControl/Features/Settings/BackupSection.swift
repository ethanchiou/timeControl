import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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

    var body: some View {
        Section {
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
            Text("JSON backup of terms, courses, blackouts, events, projects and todos.")
        }
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
