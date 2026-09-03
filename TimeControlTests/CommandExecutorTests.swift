import Foundation
import SwiftData
import Testing
import TimeControlCore
@testable import TimeControl

@MainActor
@Suite struct CommandExecutorTests {
    /// Holds the container: a `ModelContext` whose container has been deallocated traps silently on the next insert.
    struct Store {
        let container: ModelContainer
        var ctx: ModelContext { container.mainContext }
    }

    /// Wednesday, 9 September 2026 — inside the fixture term (Mon 7 Sep – Fri 18 Dec, 15 weeks).
    let today = DayKey(year: 2026, month: 9, day: 9)

    func d(_ m: Int, _ day: Int) -> DayKey { DayKey(year: 2026, month: m, day: day) }

    func makeStore(withTerm: Bool = true) throws -> Store {
        let store = Store(container: try ModelContainerFactory.make(inMemory: true))
        if withTerm {
            store.ctx.insert(Term(name: "Fall 2026", start: d(9, 7), end: d(12, 18)))
        }
        return store
    }

    func makeExecutor(_ store: Store, _ appState: AppState = AppState()) -> CommandExecutor {
        CommandExecutor(context: store.ctx, appState: appState, today: today)
    }

    func course(startWeek: Int? = nil, endWeek: Int? = nil, intervalWeeks: Int = 1) -> ParsedCommand {
        .course(CourseDraft(
            title: "CS201",
            weekdays: [.monday, .wednesday],
            startMinute: 600,
            endMinute: 690,
            intervalWeeks: intervalWeeks,
            startWeek: startWeek,
            endWeek: endWeek,
            location: "Room 204"
        ))
    }

    // MARK: Courses

    @Test func courseInsertsASeriesInTheCurrentTermAndDefaultsTheWeekBounds() throws {
        let store = try makeStore()
        let appState = AppState()
        let result = try makeExecutor(store, appState).execute(course())

        let series = try #require(try store.ctx.fetch(FetchDescriptor<Series>()).first)
        let term = try #require(series.term)
        #expect(series.title == "CS201")
        #expect(series.weekdays == [.monday, .wednesday])
        #expect(series.startMinute == 600 && series.endMinute == 690)
        #expect(series.location == "Room 204")
        #expect(series.startWeek == 1)
        #expect(series.endWeek == term.weekCount)
        #expect(term.weekCount == 15)
        #expect(result.section == .calendar)
        #expect(result.message.hasPrefix("Added CS201 · Mon/Wed "))
        #expect(result.message.hasSuffix(" · weeks 1–15"))
        // The term contains `today`, so the week view lands on this week.
        #expect(appState.weekStart == today.weekStart)
    }

    @Test func courseKeepsExplicitWeekBoundsAndInterval() throws {
        let store = try makeStore()
        try makeExecutor(store).execute(course(startWeek: 3, endWeek: 6, intervalWeeks: 2))

        let series = try #require(try store.ctx.fetch(FetchDescriptor<Series>()).first)
        #expect(series.startWeek == 3 && series.endWeek == 6)
        #expect(series.intervalWeeks == 2)
    }

    @Test func courseWithoutACurrentTermThrows() throws {
        let store = try makeStore(withTerm: false)
        let executor = makeExecutor(store)
        #expect(throws: ExecutionError.noCurrentTerm) { try executor.execute(course()) }
        #expect(try store.ctx.fetch(FetchDescriptor<Series>()).isEmpty)
        #expect(executor.preview(course()) == .failure(.noCurrentTerm))
    }

    // MARK: Events

    @Test func timedEventDefaultsToSixtyMinutes() throws {
        let store = try makeStore()
        let appState = AppState()
        let draft = EventDraft(title: "Interview", kind: .interview, day: d(9, 15), startMinute: 900)
        let result = try makeExecutor(store, appState).execute(.event(draft))

        let event = try #require(try store.ctx.fetch(FetchDescriptor<Event>()).first)
        #expect(event.title == "Interview")
        #expect(event.kind == .interview)
        #expect(!event.isAllDay)
        #expect(event.startDate == WeekMath.instant(day: d(9, 15), minute: 900))
        #expect(event.endDate == WeekMath.instant(day: d(9, 15), minute: 960))
        #expect(result.section == .today)
        #expect(result.message.hasPrefix("Added Interview · Tue Sep 15 · "))
        #expect(appState.selectedDay == d(9, 15))
        #expect(appState.weekStart == d(9, 14))
    }

    @Test func eventKeepsAnExplicitEndTime() throws {
        let store = try makeStore()
        let draft = EventDraft(title: "Dentist", kind: .appointment, day: d(9, 15), startMinute: 840, endMinute: 885)
        try makeExecutor(store).execute(.event(draft))

        let event = try #require(try store.ctx.fetch(FetchDescriptor<Event>()).first)
        #expect(event.endDate == WeekMath.instant(day: d(9, 15), minute: 885))
    }

    @Test func allDayEventSpansTheStartOfItsDay() throws {
        let store = try makeStore()
        let draft = EventDraft(title: "Move out", day: d(9, 15))
        let result = try makeExecutor(store).execute(.event(draft))

        let event = try #require(try store.ctx.fetch(FetchDescriptor<Event>()).first)
        #expect(event.isAllDay)
        #expect(event.startDate == d(9, 15).startDate())
        #expect(event.endDate == event.startDate)
        #expect(result.message == "Added Move out · Tue Sep 15 · all day")
    }

    // MARK: Todos

    @Test func todoLinksToAProjectByCaseInsensitiveTitle() throws {
        let store = try makeStore()
        let project = Project(title: "Thesis")
        store.ctx.insert(project)
        let appState = AppState()
        let draft = TodoDraft(title: "Finish lab report", priority: 1, day: d(9, 10), projectName: "thesis")
        let result = try makeExecutor(store, appState).execute(.todo(draft))

        let todo = try #require(try store.ctx.fetch(FetchDescriptor<TodoItem>()).first)
        #expect(todo.title == "Finish lab report")
        #expect(todo.priority == 1)
        #expect(todo.day == d(9, 10))
        #expect(todo.project === project)
        #expect(result.section == nil)
        #expect(result.message == "Added Finish lab report · Thu Sep 10 · Thesis")
        // Todos never move the app off the section it was on.
        #expect(appState.section == .today && appState.selectedDay == DayKey.today())
    }

    @Test func todoWithAnUnknownProjectSaysSoAndStaysUnlinked() throws {
        let store = try makeStore()
        let draft = TodoDraft(title: "Email advisor", week: d(9, 14), projectName: "Rocket")
        let result = try makeExecutor(store).execute(.todo(draft))

        let todo = try #require(try store.ctx.fetch(FetchDescriptor<TodoItem>()).first)
        #expect(todo.project == nil)
        #expect(todo.day == nil && todo.week == d(9, 14))
        #expect(result.message == "Added Email advisor · week of Mon Sep 14 · no project named Rocket")
    }

    // MARK: Blackouts

    @Test func blackoutCoversEveryDayOfTheWeekRange() throws {
        let store = try makeStore()
        let appState = AppState()
        let draft = BlackoutDraft(kinds: [.course], startWeek: 8, endWeek: 9, reason: "Fall break")
        let result = try makeExecutor(store, appState).execute(.blackout(draft))

        let blackout = try #require(try store.ctx.fetch(FetchDescriptor<Blackout>()).first)
        #expect(blackout.start == d(10, 26))
        #expect(blackout.end == d(11, 8))
        #expect(blackout.kinds == [.course])
        #expect(blackout.reason == "Fall break")
        #expect(blackout.term?.name == "Fall 2026")
        #expect(result.section == .calendar)
        #expect(result.message == "Cleared courses · weeks 8–9")
        #expect(appState.weekStart == d(10, 26))
    }

    @Test func blackoutWithoutACurrentTermThrows() throws {
        let store = try makeStore(withTerm: false)
        let executor = makeExecutor(store)
        #expect(throws: ExecutionError.noCurrentTerm) {
            try executor.execute(.blackout(BlackoutDraft(startWeek: 1, endWeek: 2)))
        }
        #expect(try store.ctx.fetch(FetchDescriptor<Blackout>()).isEmpty)
    }

    // MARK: Navigation

    @Test func navigationMovesTheAppWithoutInsertingAnything() throws {
        let store = try makeStore()
        let appState = AppState()
        let executor = makeExecutor(store, appState)

        appState.show(day: d(11, 3))
        #expect(try executor.execute(.navigate(.today)).section == nil)
        #expect(appState.selectedDay == DayKey.today())
        #expect(appState.weekStart == DayKey.today().weekStart)

        let week = try executor.execute(.navigate(.week(3)))
        #expect(week.section == .calendar)
        #expect(appState.weekStart == d(9, 21))

        #expect(try executor.execute(.navigate(.section("projects"))).section == .projects)
        #expect(throws: ExecutionError.invalid("No section named “inbox”")) {
            try executor.execute(.navigate(.section("inbox")))
        }
        #expect(try store.ctx.fetch(FetchDescriptor<Event>()).isEmpty)
    }

    @Test func weekNavigationNeedsATerm() throws {
        let store = try makeStore(withTerm: false)
        let executor = makeExecutor(store)
        #expect(throws: ExecutionError.noCurrentTerm) { try executor.execute(.navigate(.week(3))) }
    }

    // MARK: Preview and parser context

    @Test func previewDescribesCommandsWithoutMutatingTheStore() throws {
        let store = try makeStore()
        store.ctx.insert(Project(title: "Thesis"))
        let executor = makeExecutor(store)

        let commands: [ParsedCommand] = [
            course(),
            .event(EventDraft(title: "Interview", kind: .interview, day: d(9, 15), startMinute: 900)),
            .todo(TodoDraft(title: "Finish lab report", priority: 1, day: d(9, 10), projectName: "thesis")),
            .blackout(BlackoutDraft(kinds: [.course], startWeek: 8, endWeek: 9)),
            .navigate(.today),
            .navigate(.week(3)),
            .navigate(.section("todos"))
        ]
        for command in commands {
            #expect(executor.preview(command).isSuccess, "preview failed for \(command)")
        }

        let info = try executor.preview(course()).get()
        #expect(info.symbol == "book.closed")
        #expect(info.title == "New course · CS201")
        #expect(info.detail.hasSuffix("· weeks 1–15 · Fall 2026"))
        #expect(info.footnote == "Room 204")

        #expect(try store.ctx.fetch(FetchDescriptor<Series>()).isEmpty)
        #expect(try store.ctx.fetch(FetchDescriptor<Event>()).isEmpty)
        #expect(try store.ctx.fetch(FetchDescriptor<TodoItem>()).isEmpty)
        #expect(try store.ctx.fetch(FetchDescriptor<Blackout>()).isEmpty)
    }

    @Test func previewRejectsEmptyTitlesAndDaylessCourses() throws {
        let store = try makeStore()
        let executor = makeExecutor(store)
        #expect(executor.preview(.todo(TodoDraft(title: "  "))) == .failure(.invalid("Add a title")))
        let dayless = CourseDraft(title: "CS201", weekdays: [], startMinute: 600, endMinute: 690)
        #expect(executor.preview(.course(dayless)) == .failure(.invalid("Add a weekday, like Mon/Wed")))
    }

    @Test func parserContextReportsTodayActiveProjectsAndTheTerm() throws {
        let store = try makeStore()
        let active = Project(title: "Thesis")
        let done = Project(title: "Old Site")
        done.status = .done
        store.ctx.insert(active)
        store.ctx.insert(done)

        let context = makeExecutor(store).parserContext()
        #expect(context.today == today)
        #expect(context.projectNames == ["Thesis"])
        #expect(context.hasCurrentTerm)

        let termless = try makeStore(withTerm: false)
        #expect(!makeExecutor(termless).parserContext().hasCurrentTerm)
    }

    @Test func endToEndFromTheParser() throws {
        let store = try makeStore()
        let executor = makeExecutor(store)
        let parsed = try #require(QuickAddParser.parse(
            "CS201 MWF 10-11:30 @Wean 5409 weeks 1-14",
            context: executor.parserContext()
        ))
        let result = try executor.execute(parsed)

        let series = try #require(try store.ctx.fetch(FetchDescriptor<Series>()).first)
        #expect(series.title == "CS201")
        #expect(series.weekdays == [.monday, .wednesday, .friday])
        #expect(series.startWeek == 1 && series.endWeek == 14)
        #expect(series.location == "Wean 5409")
        #expect(result.message.hasSuffix(" · weeks 1–14"))
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
