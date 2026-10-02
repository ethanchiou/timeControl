import Foundation
import SwiftData
import Testing
import TimeControlCore
@testable import TimeControl

@MainActor
@Suite struct EventTaskLinkerTests {
    /// Holds the container: a context whose container was deallocated traps on the next insert.
    private struct Store {
        let container: ModelContainer
        var context: ModelContext { container.mainContext }
        init() throws { container = try ModelContainerFactory.make(inMemory: true) }
    }

    private let userID = UUID()
    private let today = DayKey(year: 2026, month: 10, day: 2)

    private func event(_ title: String, kind: Kind = .assignment, dayOffset: Int = 1, routine: Bool = false, groupID: UUID? = nil) -> Event {
        let day = today + dayOffset
        return Event(
            title: title, kind: kind,
            start: WeekMath.instant(day: day, minute: 600), end: WeekMath.instant(day: day, minute: 660),
            isRoutine: routine, groupID: groupID
        )
    }

    private func linked(in context: ModelContext) throws -> [TodoItem] {
        try context.fetch(FetchDescriptor<TodoItem>()).filter(\.isLinkedToEvent)
    }

    /// The RFC 4122 vector, so the native and web ids are the same function, not merely similar ones.
    @Test func uuid5MatchesTheRFCVector() {
        let dns = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
        #expect(EventTaskLinker.uuid5(dns, "www.example.com") == UUID(uuidString: "2ed6657d-e927-568b-95e1-2665a8aea6a2"))
    }

    @Test func todoIDIsDeterministicPerEventAndUser() {
        let eventID = UUID()
        let a = EventTaskLinker.todoID(forEvent: eventID, userID: userID)
        #expect(a == EventTaskLinker.todoID(forEvent: eventID, userID: userID), "two devices of one account derive one id")
        #expect(a != EventTaskLinker.todoID(forEvent: eventID, userID: UUID()), "two members of a group get their own todo")
        #expect(a != EventTaskLinker.todoID(forEvent: UUID(), userID: userID))
        #expect(a != EventTaskLinker.todoID(forEvent: eventID, userID: nil))
        // RFC 4122 version 5, variant 1.
        let bytes = a.uuid
        #expect(bytes.6 >> 4 == 5)
        #expect(bytes.8 >> 6 == 0b10)
    }

    @Test func nonRoutineEventsFromTodayOnGetATodoMirroringTitleAndDay() throws {
        let store = try Store()
        let exam = event("MATH240 Midterm", kind: .exam, dayOffset: 3)
        let gym = event("Gym", kind: .personal, dayOffset: 1, routine: true)
        let past = event("Old dentist", kind: .appointment, dayOffset: -2)
        let todayEvent = event("Dentist", kind: .appointment, dayOffset: 0)
        for e in [exam, gym, past, todayEvent] { store.context.insert(e) }
        try store.context.save()

        #expect(EventTaskLinker.reconcile(in: store.context, userID: userID, today: today))
        let todos = try linked(in: store.context)
        #expect(Set(todos.compactMap(\.eventID)) == [exam.uuid, todayEvent.uuid], "routine and past events get nothing")

        let examTodo = try #require(todos.first { $0.eventID == exam.uuid })
        #expect(examTodo.uuid == EventTaskLinker.todoID(forEvent: exam.uuid, userID: userID))
        #expect(examTodo.title == "MATH240 Midterm")
        #expect(examTodo.day == today + 3)
        #expect(examTodo.dueDay == today + 3)
        #expect(examTodo.priority == 1, "exams come first")
        #expect(!examTodo.isDone)

        // Idempotent: a second pass changes nothing and makes no duplicates.
        #expect(!EventTaskLinker.reconcile(in: store.context, userID: userID, today: today))
        #expect(try linked(in: store.context).count == 2)
    }

    @Test func todoFollowsTheEventsTitleAndDueDayButKeepsAMovedWorkDay() throws {
        let store = try Store()
        let e = event("Problem set 3", dayOffset: 2)
        store.context.insert(e)
        try store.context.save()
        EventTaskLinker.reconcile(in: store.context, userID: userID, today: today)
        let todo = try #require(store.context.linkedTodo(forEvent: e.uuid))

        // Renamed and moved a day later: the todo follows, work day included (it was still on the due day).
        e.title = "Problem set 3 (revised)"
        e.startDate = WeekMath.instant(day: today + 3, minute: 600)
        e.endDate = WeekMath.instant(day: today + 3, minute: 660)
        #expect(EventTaskLinker.reconcile(in: store.context, userID: userID, today: today))
        #expect(todo.title == "Problem set 3 (revised)")
        #expect(todo.dueDay == today + 3)
        #expect(todo.day == today + 3)

        // The member plans to do it early. The event moves again: the due day follows, the plan stays.
        todo.schedule(on: today + 1)
        e.startDate = WeekMath.instant(day: today + 5, minute: 600)
        e.endDate = WeekMath.instant(day: today + 5, minute: 660)
        EventTaskLinker.reconcile(in: store.context, userID: userID, today: today)
        #expect(todo.dueDay == today + 5)
        #expect(todo.day == today + 1)
    }

    @Test func deletingTheEventOrMakingItRoutineRemovesItsTodo() throws {
        let store = try Store()
        let deleted = event("Interview", kind: .interview)
        let becomesRoutine = event("Chess club", kind: .personal)
        store.context.insert(deleted)
        store.context.insert(becomesRoutine)
        try store.context.save()
        EventTaskLinker.reconcile(in: store.context, userID: userID, today: today)
        #expect(try linked(in: store.context).count == 2)

        store.context.delete(deleted)
        becomesRoutine.isRoutine = true
        try store.context.save()
        #expect(EventTaskLinker.reconcile(in: store.context, userID: userID, today: today))
        #expect(try linked(in: store.context).isEmpty)
    }

    @Test func duplicateTodosForOneEventCollapseWithoutLosingATick() throws {
        let store = try Store()
        let e = event("Lab report")
        store.context.insert(e)
        let older = TodoItem(title: "Lab report", day: today + 1, dueDay: today + 1)
        older.eventID = e.uuid
        older.createdAt = Date(timeIntervalSince1970: 1_000)
        let newer = TodoItem(title: "Lab report", day: today + 1, dueDay: today + 1)
        newer.eventID = e.uuid
        newer.createdAt = Date(timeIntervalSince1970: 2_000)
        newer.setDone(true)
        store.context.insert(older)
        store.context.insert(newer)
        try store.context.save()

        EventTaskLinker.reconcile(in: store.context, userID: userID, today: today)
        let remaining = try linked(in: store.context)
        #expect(remaining.count == 1)
        #expect(remaining.first?.uuid == older.uuid)
        #expect(remaining.first?.isDone == true)
    }

    @Test func sharedCompletionFlowsFromTheEventToTheTodoAndBack() throws {
        let store = try Store()
        let e = event("Group report", groupID: UUID())
        e.sharedCompletion = true
        store.context.insert(e)
        try store.context.save()
        EventTaskLinker.reconcile(in: store.context, userID: userID, today: today)
        let todo = try #require(store.context.linkedTodo(forEvent: e.uuid))

        // Another member finished it (arrives on the event): this member's todo is done too.
        e.setCompleted(true, by: UUID())
        #expect(EventTaskLinker.reconcile(in: store.context, userID: userID, today: today))
        #expect(todo.isDone)

        // This member reopens it from the todo: the event reopens for everyone.
        todo.setDone(false)
        #expect(e.completedAt == nil)
        #expect(!EventTaskLinker.reconcile(in: store.context, userID: userID, today: today), "already in step")

        // Ticking it again finishes the event, with this device's user as the finisher when known.
        todo.setDone(true)
        #expect(e.completedAt != nil)
    }

    @Test func individualCompletionStaysOnTheTodo() throws {
        let store = try Store()
        let e = event("Problem set", groupID: UUID())
        store.context.insert(e)
        try store.context.save()
        EventTaskLinker.reconcile(in: store.context, userID: userID, today: today)
        let todo = try #require(store.context.linkedTodo(forEvent: e.uuid))
        todo.setDone(true)
        #expect(e.completedAt == nil, "one member's problem set is not everyone's")
        #expect(!EventTaskLinker.reconcile(in: store.context, userID: userID, today: today))
        #expect(todo.isDone)

        let snapshot = ScheduleSnapshot.load(from: store.context)
        #expect(snapshot.occurrences(on: today + 1).first?.isDone == true)
    }

    @Test func setEventDoneGoesThroughTheLinkedTodo() throws {
        let store = try Store()
        let e = event("Dentist", kind: .appointment)
        store.context.insert(e)
        try store.context.save()
        EventTaskLinker.reconcile(in: store.context, userID: userID, today: today)
        store.context.setEventDone(e.uuid, true)
        #expect(store.context.linkedTodo(forEvent: e.uuid)?.isDone == true)
        #expect(RingMath.daily(try store.context.fetch(FetchDescriptor<TodoItem>()).map(\.spec), on: today + 1).done == 1)
    }
}
