import Foundation
import SwiftData
import Testing
import TimeControlCore
@testable import TimeControl

@Suite struct OccurrenceFilterTests {
    private struct Store {
        let container: ModelContainer
        var context: ModelContext { container.mainContext }
        init() throws { container = try ModelContainerFactory.make(inMemory: true) }
    }

    private func occurrence(routine: Bool, groupID: UUID? = nil) -> Occurrence {
        Occurrence(source: .event(id: UUID()), title: "x", kind: .other, day: .today(), start: Date(), end: Date(), isRoutine: routine, groupID: groupID)
    }

    @Test func emptyFilterHidesNothing() {
        let filter: OccurrenceFilter = []
        #expect(!filter.hides(occurrence(routine: true)))
        #expect(!filter.hides(occurrence(routine: false, groupID: UUID())))
    }

    @Test func flagsAreIndependent() {
        #expect(OccurrenceFilter.routine.hides(occurrence(routine: true)))
        #expect(!OccurrenceFilter.routine.hides(occurrence(routine: false, groupID: UUID())))
        #expect(OccurrenceFilter.group.hides(occurrence(routine: false, groupID: UUID())))
        #expect(!OccurrenceFilter.group.hides(occurrence(routine: true)))
        let both: OccurrenceFilter = [.routine, .group]
        #expect(both.hides(occurrence(routine: true)))
        #expect(both.hides(occurrence(routine: false, groupID: UUID())))
        #expect(!both.hides(occurrence(routine: false)))
    }

    @Test func appStateOpensMonthWithBothFlagsOn() {
        let state = AppState()
        state.section = .calendar
        state.calendarScale = .month
        #expect(state.hidesRoutine && state.hidesGroup)
        #expect(state.hiddenFilter == [.routine, .group])
        state.calendarScale = .week
        #expect(!state.hidesRoutine && !state.hidesGroup)
        #expect(state.hiddenFilter == [])
    }

    @Test func groupFlagRemembersPerScaleAndUpcomingSeparately() {
        let state = AppState()
        state.section = .calendar
        state.calendarScale = .day
        state.hidesGroup = true
        state.calendarScale = .week
        #expect(!state.hidesGroup)
        state.calendarScale = .day
        #expect(state.hidesGroup)
        state.section = .upcoming
        #expect(state.hidesRoutine && !state.hidesGroup)
        state.hidesGroup = true
        state.section = .today
        #expect(state.hidesGroup, "Today shares the day scale's flag")
    }

    @Test func groupEventsPaintInTheMembersColourForTheGroup() throws {
        let store = try Store()
        let group = SharedGroup(uuid: UUID(), name: "Study", colorHex: "#10B981", joinCode: "ABCD2345", createdBy: UUID(), role: "member")
        store.context.insert(group)
        let now = Date()
        let mine = Event(title: "Mine", kind: .exam, start: now, end: now.addingTimeInterval(3600))
        mine.colorHex = "#EC4899"
        let shared = Event(title: "Shared", kind: .exam, start: now, end: now.addingTimeInterval(3600), groupID: group.uuid)
        shared.colorHex = "#EC4899"
        store.context.insert(mine)
        store.context.insert(shared)

        let snapshot = ScheduleSnapshot(series: [], events: [mine, shared], blackouts: [], exceptions: [], groups: [group])
        let byTitle = Dictionary(uniqueKeysWithValues: snapshot.occurrences(on: DayKey(now)).map { ($0.title, $0) })
        #expect(byTitle["Mine"]?.colorHex == "#EC4899")
        #expect(byTitle["Shared"]?.colorHex == "#10B981", "the group's colour wins over the event's own")
        #expect(byTitle["Shared"]?.isGroup == true)
        #expect(byTitle["Shared"]?.groupID == group.uuid)

        group.colorOverrideHex = "#F59E0B"
        let overridden = ScheduleSnapshot(series: [], events: [shared], blackouts: [], exceptions: [], groups: [group])
        #expect(overridden.occurrences(on: DayKey(now)).first?.colorHex == "#F59E0B")

        let hidden = snapshot.occurrences(on: DayKey(now), hiding: .group)
        #expect(hidden.map(\.title) == ["Mine"])
    }

    @Test func aGroupEventWhoseGroupIsUnknownKeepsItsOwnColour() throws {
        let now = Date()
        let orphan = Event(title: "Orphan", kind: .personal, start: now, end: now.addingTimeInterval(600), groupID: UUID())
        let snapshot = ScheduleSnapshot(series: [], events: [orphan], blackouts: [], exceptions: [], groups: [])
        #expect(snapshot.occurrences(on: DayKey(now)).first?.colorHex == Kind.personal.colorHex)
    }
}
