import Foundation
import SwiftData
import Testing
import TimeControlCore
@testable import TimeControl

@MainActor
@Suite struct ModelTests {
    /// Holds the container: a `ModelContext` whose container has been deallocated traps silently on the next insert.
    struct Store {
        let container: ModelContainer
        var ctx: ModelContext { container.mainContext }
    }

    func makeStore() throws -> Store {
        Store(container: try ModelContainerFactory.make(inMemory: true))
    }

    func d(_ m: Int, _ day: Int) -> DayKey { DayKey(year: 2026, month: m, day: day) }

    @Test func everyModelRoundTripsThroughSpecs() throws {
        let store = try makeStore()
        let ctx = store.ctx
        let term = Term(name: "Fall 2026", start: d(9, 7), end: d(12, 18))
        ctx.insert(term)
        let cs = Series(title: "CS201", weekdays: [.monday, .wednesday], startMinute: 600, endMinute: 690, intervalWeeks: 2, startWeek: 2, endWeek: 14, location: "Room 204")
        cs.term = term
        ctx.insert(cs)
        let skip = OccurrenceException(series: cs, day: d(9, 16))
        ctx.insert(skip)
        let blackout = Blackout(start: d(10, 26), end: d(11, 8), kinds: [.course], reason: "Exams", term: term)
        ctx.insert(blackout)
        let event = Event(title: "Interview", kind: .interview, start: Date(timeIntervalSince1970: 1_800_000_000), end: Date(timeIntervalSince1970: 1_800_003_600))
        ctx.insert(event)
        let project = Project(title: "Thesis", priority: 1, targetDay: d(12, 1))
        ctx.insert(project)
        let todo = TodoItem(title: "Outline", priority: 2, day: d(9, 9), project: project)
        ctx.insert(todo)
        try ctx.save()

        #expect(term.weekCount == 15)
        #expect(term.series?.count == 1)
        #expect(term.blackouts?.count == 1)
        #expect(cs.exceptions?.count == 1)
        #expect(project.todos?.count == 1)

        let spec = try #require(cs.spec)
        #expect(spec.term.id == term.uuid)
        #expect(spec.weekdays == [.monday, .wednesday])
        #expect(spec.intervalWeeks == 2 && spec.startWeek == 2 && spec.endWeek == 14)
        #expect(skip.spec.seriesID == cs.uuid && skip.spec.day == d(9, 16))
        #expect(blackout.spec.kinds == [.course] && blackout.summary == "Courses · weeks 8–9")
        #expect(event.spec.kind == .interview && event.reminderOffsetsMinutes == [60])
        #expect(todo.spec.projectID == project.uuid && todo.spec.day == d(9, 9))
        #expect(project.progress.total == 1 && project.progress.done == 0)

        let snapshot = ScheduleSnapshot.load(from: ctx)
        let sept = snapshot.occurrences(in: d(9, 7)...d(9, 20))
        // Biweekly from week 2: Sep 14 (Mon) and Sep 16 (Wed), but Sep 16 is skipped.
        #expect(sept.map(\.day) == [d(9, 14)])
        let exams = snapshot.occurrences(in: d(10, 26)...d(10, 28), includeSuppressed: true)
        #expect(exams.count == 2 && exams.allSatisfy(\.isSuppressed))
        #expect(snapshot.occurrences(in: d(10, 26)...d(10, 28)).isEmpty)
    }

    @Test func deletingATermCascadesToItsCoursesAndBlackouts() throws {
        let store = try makeStore()
        let ctx = store.ctx
        let term = Term(name: "T", start: d(9, 7), end: d(12, 18))
        ctx.insert(term)
        let s = Series(title: "X", weekdays: [.friday], startMinute: 540, endMinute: 600, endWeek: 10)
        s.term = term
        ctx.insert(s)
        ctx.insert(Blackout(start: d(10, 1), end: d(10, 2), term: term))
        try ctx.save()
        ctx.delete(term)
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<Series>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Blackout>()).isEmpty)
    }

    @Test func todoSchedulingHelpersKeepDayAndWeekExclusive() throws {
        let store = try makeStore()
        let ctx = store.ctx
        let todo = TodoItem(title: "A")
        ctx.insert(todo)
        todo.schedule(on: d(9, 10))
        #expect(todo.day == d(9, 10) && todo.week == nil)
        todo.schedule(inWeekOf: d(9, 10))
        #expect(todo.day == nil && todo.week == d(9, 7))
        todo.setDone(true)
        #expect(todo.isDone && todo.completedAt != nil)
        todo.setDone(false)
        #expect(!todo.isDone && todo.completedAt == nil)
    }

    @Test func currentTermPrefersActiveThenUpcomingThenPast() throws {
        let store = try makeStore()
        let ctx = store.ctx
        let past = Term(name: "Spring", start: d(1, 12), end: d(5, 1))
        let fall = Term(name: "Fall", start: d(9, 7), end: d(12, 18))
        ctx.insert(past)
        ctx.insert(fall)
        try ctx.save()
        #expect(ctx.currentTerm(on: d(10, 1))?.name == "Fall")
        #expect(ctx.currentTerm(on: d(7, 1))?.name == "Fall")
        #expect(ctx.currentTerm(on: DayKey(year: 2027, month: 1, day: 5))?.name == "Fall")
        fall.isArchived = true
        try ctx.save()
        #expect(ctx.currentTerm(on: d(10, 1))?.name == "Spring")
    }
}
