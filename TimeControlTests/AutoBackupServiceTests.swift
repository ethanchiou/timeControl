import Foundation
import SwiftData
import Testing
import TimeControlCore
@testable import TimeControl

/// Keeps the container alive alongside the context: a context whose container has been deallocated
/// traps on the next insert.
@MainActor
private struct Store {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
    }

    /// One term with one course, so the store is non-empty.
    func seed(termName: String = "Fall") {
        let term = Term(name: termName, start: DayKey.today(), end: DayKey.today() + 90)
        context.insert(term)
        let series = Series(title: "MATH240", weekdays: [.monday], startMinute: 540, endMinute: 620, endWeek: 12)
        context.insert(series)
        series.term = term
    }
}

/// A scratch directory per test, removed afterwards.
private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let url = URL.temporaryDirectory.appending(path: "AutoBackupTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    try body(url)
}

@MainActor
@Suite struct AutoBackupServiceTests {
    @Test func writeCreatesADatedFileNamedForTheDay() throws {
        let store = try Store()
        store.seed()
        try withTemporaryDirectory { dir in
            let day = DayKey(rawValue: 9000)
            let url = try AutoBackupService.write(BackupService.export(from: store.context), to: dir, day: day)

            #expect(url.lastPathComponent == BackupService.suggestedFilename(now: day.startDate()))
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func theWrittenFileDecodesBackToTheSameRecords() throws {
        let store = try Store()
        store.seed(termName: "Spring 2027")
        try withTemporaryDirectory { dir in
            let url = try AutoBackupService.write(BackupService.export(from: store.context), to: dir)

            let restored = try BackupDocument.decode(try Data(contentsOf: url))
            #expect(restored.terms.map(\.name) == ["Spring 2027"])
            #expect(restored.series.map(\.title) == ["MATH240"])
        }
    }

    @Test func rerunningOnTheSameDayOverwritesRatherThanAccumulates() throws {
        let store = try Store()
        store.seed()
        try withTemporaryDirectory { dir in
            let day = DayKey(rawValue: 9000)
            try AutoBackupService.write(BackupService.export(from: store.context), to: dir, day: day)
            try AutoBackupService.write(BackupService.export(from: store.context), to: dir, day: day)

            #expect(AutoBackupService.existingBackups(in: dir).count == 1)
        }
    }

    @Test func rotationKeepsOnlyTheNewestFiles() throws {
        let store = try Store()
        store.seed()
        try withTemporaryDirectory { dir in
            let document = try BackupService.export(from: store.context)
            for offset in 0..<10 {
                try AutoBackupService.write(document, to: dir, day: DayKey(rawValue: 9000 + offset), keeping: 3)
            }

            let names = AutoBackupService.existingBackups(in: dir).map(\.lastPathComponent)
            let expected = (7..<10).reversed().map {
                BackupService.suggestedFilename(now: DayKey(rawValue: 9000 + $0).startDate())
            }
            #expect(names == expected)
        }
    }

    @Test func existingBackupsIgnoresUnrelatedFilesAndSortsNewestFirst() throws {
        try withTemporaryDirectory { dir in
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for name in ["TimeControl-2026-01-02.json", "TimeControl-2026-03-04.json", "notes.txt", "TimeControl-old.csv"] {
                try Data("{}".utf8).write(to: dir.appending(path: name))
            }

            let names = AutoBackupService.existingBackups(in: dir).map(\.lastPathComponent)
            #expect(names == ["TimeControl-2026-03-04.json", "TimeControl-2026-01-02.json"])
        }
    }

    @Test func existingBackupsIsEmptyWhenTheDirectoryHasNeverBeenCreated() {
        let missing = URL.temporaryDirectory.appending(path: "AutoBackupTests-missing-\(UUID().uuidString)")
        #expect(AutoBackupService.existingBackups(in: missing).isEmpty)
    }

    // MARK: The once-a-day gate
    //
    // `runIfNeeded` reads real UserDefaults, so each of these restores what it found.

    /// Runs `body` with the auto-backup defaults isolated, restoring them afterwards.
    private func withSettings(enabled: Bool, lastRun: DayKey?, _ body: (URL) throws -> Void) throws {
        let savedEnabled = AutoBackupService.isEnabled
        let savedLastRun = AutoBackupService.lastRunDay
        defer {
            AutoBackupService.isEnabled = savedEnabled
            AutoBackupService.lastRunDay = savedLastRun
        }
        AutoBackupService.isEnabled = enabled
        AutoBackupService.lastRunDay = lastRun
        try withTemporaryDirectory { try body($0) }
    }

    @Test func runIfNeededWritesTheFirstTimeAndRecordsTheDay() throws {
        let store = try Store()
        store.seed()
        let today = DayKey(rawValue: 9500)
        try withSettings(enabled: true, lastRun: nil) { dir in
            let url = AutoBackupService.runIfNeeded(in: store.context, to: dir, today: today)

            #expect(url != nil)
            #expect(AutoBackupService.lastRunDay == today)
        }
    }

    @Test func runIfNeededSkipsWhenOneAlreadyRanToday() throws {
        let store = try Store()
        store.seed()
        let today = DayKey(rawValue: 9500)
        try withSettings(enabled: true, lastRun: today) { dir in
            #expect(AutoBackupService.runIfNeeded(in: store.context, to: dir, today: today) == nil)
            #expect(AutoBackupService.existingBackups(in: dir).isEmpty)
        }
    }

    @Test func runIfNeededWritesAgainOnceTheDayRollsOver() throws {
        let store = try Store()
        store.seed()
        try withSettings(enabled: true, lastRun: DayKey(rawValue: 9500)) { dir in
            let url = AutoBackupService.runIfNeeded(in: store.context, to: dir, today: DayKey(rawValue: 9501))

            #expect(url != nil)
            #expect(AutoBackupService.lastRunDay == DayKey(rawValue: 9501))
        }
    }

    /// Restoring an old backup can leave the recorded day in the future; that must not wedge backups off.
    @Test func runIfNeededSkipsWhenTheRecordedDayIsInTheFuture() throws {
        let store = try Store()
        store.seed()
        try withSettings(enabled: true, lastRun: DayKey(rawValue: 9600)) { dir in
            #expect(AutoBackupService.runIfNeeded(in: store.context, to: dir, today: DayKey(rawValue: 9500)) == nil)
        }
    }

    @Test func runIfNeededDoesNothingWhenDisabled() throws {
        let store = try Store()
        store.seed()
        try withSettings(enabled: false, lastRun: nil) { dir in
            #expect(AutoBackupService.runIfNeeded(in: store.context, to: dir, today: DayKey(rawValue: 9500)) == nil)
            #expect(AutoBackupService.existingBackups(in: dir).isEmpty)
        }
    }

    /// A fresh install must not write an empty file, and must not burn the day doing it.
    @Test func runIfNeededSkipsAnEmptyStoreWithoutRecordingTheDay() throws {
        let store = try Store()
        try withSettings(enabled: true, lastRun: nil) { dir in
            #expect(AutoBackupService.runIfNeeded(in: store.context, to: dir, today: DayKey(rawValue: 9500)) == nil)
            #expect(AutoBackupService.existingBackups(in: dir).isEmpty)
            #expect(AutoBackupService.lastRunDay == nil)
        }
    }

    @Test func writeCreatesTheDirectoryWhenItIsMissing() throws {
        let store = try Store()
        store.seed()
        try withTemporaryDirectory { dir in
            let nested = dir.appending(path: "deeper")
            let url = try AutoBackupService.write(BackupService.export(from: store.context), to: nested)

            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }
}
