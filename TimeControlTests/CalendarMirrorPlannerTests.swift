import Foundation
import Testing
import TimeControlCore
@testable import TimeControl

@MainActor
@Suite struct CalendarMirrorPlannerTests {
    let calendar = Calendar.app(timeZone: TimeZone(identifier: "UTC")!)
    let day = DayKey(year: 2026, month: 9, day: 9)

    let allKinds = Set(Kind.allCases)

    func seriesOcc(
        kind: Kind = .course,
        title: String = "MATH240 Linear Algebra",
        startMinute: Int = 9 * 60,
        endMinute: Int = 10 * 60 + 20,
        isAllDay: Bool = false,
        location: String = "Science 110",
        suppressedBy: UUID? = nil,
        seriesID: UUID = UUID()
    ) -> Occurrence {
        Occurrence(
            source: .series(id: seriesID, day: day),
            title: title,
            kind: kind,
            day: day,
            start: WeekMath.instant(day: day, minute: startMinute, calendar: calendar),
            end: WeekMath.instant(day: day, minute: endMinute, calendar: calendar),
            isAllDay: isAllDay,
            location: location,
            suppressedBy: suppressedBy
        )
    }

    func eventOcc(
        id: UUID,
        kind: Kind = .exam,
        title: String = "MATH240 Midterm",
        startMinute: Int = 9 * 60,
        endMinute: Int = 11 * 60,
        isAllDay: Bool = false,
        location: String = ""
    ) -> Occurrence {
        Occurrence(
            source: .event(id: id),
            title: title,
            kind: kind,
            day: day,
            start: WeekMath.instant(day: day, minute: startMinute, calendar: calendar),
            end: WeekMath.instant(day: day, minute: endMinute, calendar: calendar),
            isAllDay: isAllDay,
            location: location
        )
    }

    func desired(
        _ occurrences: [Occurrence],
        mirroredKinds: Set<Kind>? = nil,
        alarmsEnabled: Bool = true,
        eventOffsets: [UUID: [Int]] = [:]
    ) -> [MirrorEvent] {
        CalendarMirrorPlanner.desired(
            occurrences: occurrences,
            mirroredKinds: mirroredKinds ?? allKinds,
            alarmsEnabled: alarmsEnabled,
            eventOffsets: eventOffsets,
            calendar: calendar
        )
    }

    // MARK: desired

    @Test func mirrorsOccurrenceFieldsAndKey() {
        let occ = seriesOcc()
        let events = desired([occ])
        #expect(events.count == 1)
        #expect(events[0].key == occ.id)
        #expect(events[0].title == "MATH240 Linear Algebra")
        #expect(events[0].start == occ.start)
        #expect(events[0].end == occ.end)
        #expect(events[0].isAllDay == false)
        #expect(events[0].location == "Science 110")
        #expect(events[0].notes == MirrorEvent.managedNote)
        #expect(events[0].kind == .course)
    }

    @Test func dropsSuppressedOccurrences() {
        #expect(desired([seriesOcc(suppressedBy: UUID())]).isEmpty)
    }

    @Test func dropsKindsThatAreNotMirrored() {
        let course = seriesOcc(kind: .course)
        let personal = seriesOcc(kind: .personal)
        let events = desired([course, personal], mirroredKinds: [.course])
        #expect(events.map(\.key) == [course.id])
    }

    @Test func seriesAlarmUsesKindDefaultLeadTime() {
        #expect(desired([seriesOcc(kind: .course)])[0].alarmMinutes == [10])
        #expect(desired([seriesOcc(kind: .exam)])[0].alarmMinutes == [60])
    }

    @Test func seriesWithNoDefaultReminderGetsNoAlarm() {
        #expect(desired([seriesOcc(kind: .personal)])[0].alarmMinutes.isEmpty)
    }

    @Test func eventAlarmsComeFromEventOffsets() {
        let id = UUID()
        let events = desired([eventOcc(id: id)], eventOffsets: [id: [60, 10]])
        #expect(events[0].alarmMinutes == [10, 60])
    }

    @Test func eventWithNoOffsetsGetsNoAlarmEvenWhenItsKindHasADefault() {
        let id = UUID()
        let events = desired([eventOcc(id: id, kind: .exam)], eventOffsets: [:])
        #expect(events[0].alarmMinutes.isEmpty)
    }

    @Test func alarmsDisabledStripsEveryAlarm() {
        let id = UUID()
        let events = desired([seriesOcc(), eventOcc(id: id)], alarmsEnabled: false, eventOffsets: [id: [30]])
        #expect(events.allSatisfy { $0.alarmMinutes.isEmpty })
    }

    @Test func allDayEventStartsAtDayStartAndIsZeroLength() {
        let id = UUID()
        let occ = eventOcc(id: id, startMinute: 14 * 60, endMinute: 16 * 60, isAllDay: true)
        let event = desired([occ])[0]
        #expect(event.isAllDay)
        #expect(event.start == day.startDate(in: calendar))
        #expect(event.end == event.start)
    }

    // MARK: url round trip

    @Test func urlAndKeyRoundTrip() {
        for key in [seriesOcc().id, eventOcc(id: UUID()).id] {
            #expect(MirrorEvent.key(from: MirrorEvent.url(for: key)) == key)
        }
    }

    @Test func keyIsNilForForeignUrls() {
        #expect(MirrorEvent.key(from: nil) == nil)
        #expect(MirrorEvent.key(from: URL(string: "https://example.com/occ/abc")) == nil)
        #expect(MirrorEvent.key(from: URL(string: "timecontrol://todo/abc")) == nil)
        #expect(MirrorEvent.key(from: URL(string: "timecontrol://occ/")) == nil)
    }

    // MARK: diff

    func mirror(_ key: String, title: String = "Class", alarms: [Int] = [], location: String = "", isAllDay: Bool = false) -> MirrorEvent {
        MirrorEvent(
            key: key,
            title: title,
            start: WeekMath.instant(day: day, minute: 9 * 60, calendar: calendar),
            end: WeekMath.instant(day: day, minute: 10 * 60, calendar: calendar),
            isAllDay: isAllDay,
            location: location,
            notes: MirrorEvent.managedNote,
            alarmMinutes: alarms,
            kind: .course
        )
    }

    @Test func missingEventsAreCreated() {
        let diff = CalendarMirrorPlanner.diff(desired: [mirror("a"), mirror("b")], existing: [])
        #expect(diff.create.map(\.key) == ["a", "b"])
        #expect(diff.update.isEmpty)
        #expect(diff.delete.isEmpty)
    }

    @Test func identicalEventsAreANoOp() {
        let event = mirror("a", alarms: [10], location: "Science 110")
        let diff = CalendarMirrorPlanner.diff(
            desired: [event],
            existing: [ExistingMirrorEvent(identifier: "ek-1", event: event)]
        )
        #expect(diff.isEmpty)
    }

    @Test func differingNotesAndKindDoNotCauseAnUpdate() {
        var stale = mirror("a")
        stale.notes = "user typed something"
        stale.kind = .other
        let diff = CalendarMirrorPlanner.diff(
            desired: [mirror("a")],
            existing: [ExistingMirrorEvent(identifier: "ek-1", event: stale)]
        )
        #expect(diff.isEmpty)
    }

    @Test(arguments: [
        "title", "start", "end", "isAllDay", "location", "alarms",
    ])
    func anyChangedFieldCausesAnUpdate(field: String) {
        let wanted = mirror("a", title: "Class", alarms: [10], location: "Science 110")
        var stale = wanted
        switch field {
        case "title": stale.title = "Old name"
        case "start": stale.start = wanted.start.addingTimeInterval(-3600)
        case "end": stale.end = wanted.end.addingTimeInterval(3600)
        case "isAllDay": stale.isAllDay = true
        case "location": stale.location = "Science 220"
        default: stale.alarmMinutes = [30]
        }
        let diff = CalendarMirrorPlanner.diff(
            desired: [wanted],
            existing: [ExistingMirrorEvent(identifier: "ek-1", event: stale)]
        )
        #expect(diff.create.isEmpty)
        #expect(diff.delete.isEmpty)
        #expect(diff.update == [MirrorUpdate(identifier: "ek-1", event: wanted)])
    }

    @Test func reorderedAlarmsAreNotAChange() {
        let wanted = mirror("a", alarms: [10, 60])
        var stale = wanted
        stale.alarmMinutes = [60, 10]
        let diff = CalendarMirrorPlanner.diff(
            desired: [wanted],
            existing: [ExistingMirrorEvent(identifier: "ek-1", event: stale)]
        )
        #expect(diff.isEmpty)
    }

    @Test func existingEventsThatAreNoLongerWantedAreDeleted() {
        let diff = CalendarMirrorPlanner.diff(
            desired: [mirror("a")],
            existing: [
                ExistingMirrorEvent(identifier: "ek-1", event: mirror("a")),
                ExistingMirrorEvent(identifier: "ek-2", event: mirror("gone")),
            ]
        )
        #expect(diff.create.isEmpty)
        #expect(diff.update.isEmpty)
        #expect(diff.delete == ["ek-2"])
    }

    @Test func foreignEventsAreLeftAlone() {
        let diff = CalendarMirrorPlanner.diff(
            desired: [],
            existing: [ExistingMirrorEvent(identifier: "ek-foreign", event: mirror(""))]
        )
        #expect(diff.isEmpty)
    }

    @Test func duplicateKeysKeepTheLowestIdentifierAndDeleteTheRest() {
        let wanted = mirror("a", title: "New name")
        let diff = CalendarMirrorPlanner.diff(
            desired: [wanted],
            existing: [
                ExistingMirrorEvent(identifier: "ek-2", event: mirror("a")),
                ExistingMirrorEvent(identifier: "ek-1", event: mirror("a")),
            ]
        )
        #expect(diff.update == [MirrorUpdate(identifier: "ek-1", event: wanted)])
        #expect(diff.delete == ["ek-2"])
    }

    @Test func outputIsSortedByKeyRegardlessOfInputOrder() {
        let desiredEvents = [mirror("c"), mirror("a"), mirror("b")]
        let existing = [
            ExistingMirrorEvent(identifier: "ek-z", event: mirror("z")),
            ExistingMirrorEvent(identifier: "ek-y", event: mirror("y")),
        ]
        let diff = CalendarMirrorPlanner.diff(desired: desiredEvents, existing: existing)
        #expect(diff.create.map(\.key) == ["a", "b", "c"])
        #expect(diff.delete == ["ek-y", "ek-z"])
        #expect(CalendarMirrorPlanner.diff(desired: desiredEvents.reversed(), existing: existing.reversed()) == diff)
    }
}
