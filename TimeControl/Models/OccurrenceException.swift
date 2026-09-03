import Foundation
import SwiftData
import TimeControlCore

extension SchemaV1 {
    /// A per-occurrence override of a series. v1 supports only `skipped`.
    @Model
    final class OccurrenceException {
        var uuid: UUID = UUID()
        var dayKey: Int = 0
        var kindRaw: String = ExceptionKind.skipped.rawValue
        var createdAt: Date = Date()

        var series: Series?

        init(series: Series, day: DayKey, kind: ExceptionKind = .skipped) {
            self.series = series
            self.dayKey = day.rawValue
            self.kindRaw = kind.rawValue
        }
    }
}

extension OccurrenceException {
    var day: DayKey {
        get { DayKey(rawValue: dayKey) }
        set { dayKey = newValue.rawValue }
    }

    var kind: ExceptionKind {
        get { ExceptionKind(rawValue: kindRaw) ?? .skipped }
        set { kindRaw = newValue.rawValue }
    }

    var spec: ExceptionSpec {
        ExceptionSpec(id: uuid, seriesID: series?.uuid ?? UUID(), day: day, kind: kind)
    }
}
