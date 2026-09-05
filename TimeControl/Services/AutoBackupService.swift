import Foundation
import SwiftData
import TimeControlCore

/// Writes a dated JSON backup into the app container once a day, keeping the last ``keepCount`` files.
///
/// This is the "undo a bad day" tier: it survives a corrupted store, a failed migration, a bad import
/// and an accidental delete. It lives inside the sandbox container, so it does *not* survive deleting
/// the app or losing the device — that still needs a manual "Export Backup…" to somewhere else.
@MainActor
enum AutoBackupService {
    /// `UserDefaults` key. A missing value means enabled.
    static let enabledKey = "autoBackup.enabled"
    static let lastRunKey = "autoBackup.lastRunDayKey"

    /// How many dated files to keep. One per day, so this is a week of history.
    static let keepCount = 7

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// The day the last automatic backup was written, or nil if none ever has been.
    static var lastRunDay: DayKey? {
        get { (UserDefaults.standard.object(forKey: lastRunKey) as? Int).map(DayKey.init(rawValue:)) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: lastRunKey) }
    }

    /// `Application Support/Backups` inside the container. Created on first use.
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return base.appending(path: "Backups", directoryHint: .isDirectory)
    }

    /// Every backup this service has written, newest first. Filenames are `yyyy-MM-dd`, which sorts
    /// lexicographically the same way it sorts chronologically.
    static func existingBackups(in directory: URL = directory) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { $0.lastPathComponent.hasPrefix("TimeControl-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Writes `day`'s backup and prunes the directory down to `keeping` files. Rerunning on the same
    /// day overwrites that day's file rather than adding another.
    @discardableResult
    static func write(
        _ document: BackupDocument,
        to directory: URL = directory,
        day: DayKey = .today(),
        keeping keepCount: Int = keepCount
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: BackupService.suggestedFilename(now: day.startDate()))
        try document.encode().write(to: url, options: .atomic)
        for stale in existingBackups(in: directory).dropFirst(keepCount) {
            try? FileManager.default.removeItem(at: stale)
        }
        return url
    }

    /// The once-a-day gate, called when the app becomes active. Returns the file written, or nil when
    /// backups are off, one already ran today, or there is nothing yet to back up.
    ///
    /// A backup must never take the app down with it, so a write failure is logged and swallowed.
    @discardableResult
    static func runIfNeeded(
        in context: ModelContext,
        to directory: URL = directory,
        today: DayKey = .today()
    ) -> URL? {
        guard isEnabled else { return nil }
        if let lastRunDay, lastRunDay >= today { return nil }
        // A fresh install has nothing worth keeping, and an empty file would just crowd out real ones.
        guard let document = try? BackupService.export(from: context), !document.isEmpty else { return nil }
        do {
            let url = try write(document, to: directory, day: today)
            lastRunDay = today
            return url
        } catch {
            print("AutoBackupService: write failed: \(error)")
            return nil
        }
    }
}
