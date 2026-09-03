import Foundation
import SwiftData
import TimeControlCore

extension SchemaV1 {
    /// Suppresses recurring occurrences of the given kinds (empty = all) over a day range.
    /// Non-destructive: deleting the blackout restores the occurrences.
    @Model
    final class Blackout {
        var uuid: UUID = UUID()
        var startDayKey: Int = 0
        var endDayKey: Int = 0
        var kindsRaw: [String] = []
        var reason: String = ""
        var createdAt: Date = Date()

        /// Display grouping only; the engine works from the day range.
        var term: Term?

        init(start: DayKey, end: DayKey, kinds: Set<Kind> = [], reason: String = "", term: Term? = nil) {
            self.startDayKey = start.rawValue
            self.endDayKey = max(end, start).rawValue
            self.kindsRaw = kinds.map(\.rawValue).sorted()
            self.reason = reason
            self.term = term
        }
    }
}

extension Blackout {
    var start: DayKey {
        get { DayKey(rawValue: startDayKey) }
        set { startDayKey = newValue.rawValue }
    }

    var end: DayKey {
        get { DayKey(rawValue: endDayKey) }
        set { endDayKey = newValue.rawValue }
    }

    var kinds: Set<Kind> {
        get { Set(kindsRaw.compactMap(Kind.init(rawValue:))) }
        set { kindsRaw = newValue.map(\.rawValue).sorted() }
    }

    var spec: BlackoutSpec {
        BlackoutSpec(id: uuid, start: start, end: end, kinds: kinds, reason: reason)
    }

    /// "Courses · weeks 8–9" style summary, relative to `term` when it has one.
    var summary: String {
        let what = kinds.isEmpty ? "Everything" : kinds.sorted { $0.rawValue < $1.rawValue }.map(\.pluralName).joined(separator: ", ")
        if let term, let a = term.weekNumber(of: start), let b = term.weekNumber(of: end) {
            return a == b ? "\(what) · week \(a)" : "\(what) · weeks \(a)–\(b)"
        }
        return "\(what) · \(start.description) – \(end.description)"
    }
}
