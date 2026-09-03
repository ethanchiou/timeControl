import Foundation
import SwiftData
import TimeControlCore

extension ModelContext {
    func series(uuid: UUID) -> Series? {
        var d = FetchDescriptor<Series>(predicate: #Predicate { $0.uuid == uuid })
        d.fetchLimit = 1
        return try? fetch(d).first
    }

    func event(uuid: UUID) -> Event? {
        var d = FetchDescriptor<Event>(predicate: #Predicate { $0.uuid == uuid })
        d.fetchLimit = 1
        return try? fetch(d).first
    }

    func project(uuid: UUID) -> Project? {
        var d = FetchDescriptor<Project>(predicate: #Predicate { $0.uuid == uuid })
        d.fetchLimit = 1
        return try? fetch(d).first
    }

    func blackout(uuid: UUID) -> Blackout? {
        var d = FetchDescriptor<Blackout>(predicate: #Predicate { $0.uuid == uuid })
        d.fetchLimit = 1
        return try? fetch(d).first
    }

    /// Skip one occurrence of a series. Idempotent.
    @discardableResult
    func skip(seriesID: UUID, on day: DayKey) -> OccurrenceException? {
        guard let series = series(uuid: seriesID) else { return nil }
        if let existing = (series.exceptions ?? []).first(where: { $0.day == day }) { return existing }
        let exception = OccurrenceException(series: series, day: day)
        insert(exception)
        return exception
    }

    /// Delete whatever an occurrence came from: the series exception restore, the event, or (for a series) the whole series.
    func deleteSource(of occurrence: Occurrence) {
        switch occurrence.source {
        case .event(let id):
            if let e = event(uuid: id) { delete(e) }
        case .series(let id, _):
            if let s = series(uuid: id) { delete(s) }
        }
    }
}
