import Foundation
import SwiftData
import TimeControlCore

/// What `CommandExecutor.execute` did: a transient confirmation and, when it makes sense, the
/// section the palette should leave the app in.
struct ExecutionResult: Equatable {
    var message: String
    var section: AppSection?
}

enum ExecutionError: Error, Equatable {
    /// Courses, blackouts and week navigation need a term to be relative to.
    case noCurrentTerm
    case invalid(String)
}

/// One command rendered for the palette's live preview.
struct PreviewInfo: Equatable {
    var symbol: String
    var title: String
    var detail: String
    var footnote: String?
}

/// Turns `QuickAddParser` output into SwiftData inserts and `AppState` navigation.
///
/// `preview` and `execute` agree by construction: `execute` runs `preview` first and throws whatever
/// it rejected, so anything the palette shows as ready can be committed with Return.
@MainActor
struct CommandExecutor {
    let context: ModelContext
    let appState: AppState
    var today: DayKey = .today()

    // MARK: Parsing

    /// Today, the titles of active projects (for `#Tag`) and whether courses are possible at all.
    func parserContext() -> QuickAddContext {
        QuickAddContext(
            today: today,
            projectNames: projects().filter { $0.status == .active }.map(\.title),
            hasCurrentTerm: currentTerm() != nil
        )
    }

    // MARK: Preview

    /// Describes what `command` would do. Reads the store but never writes to it.
    func preview(_ command: ParsedCommand) -> Result<PreviewInfo, ExecutionError> {
        switch command {
        case .course(let draft):
            guard let term = currentTerm() else { return .failure(.noCurrentTerm) }
            let name = trimmed(draft.title)
            guard !name.isEmpty else { return .failure(.invalid("Add a course title")) }
            guard !draft.weekdays.isEmpty else { return .failure(.invalid("Add a weekday, like Mon/Wed")) }
            let weeks = weekBounds(draft, in: term)
            var detail = [schedule(draft), weeksLabel(weeks)]
            if draft.intervalWeeks > 1 { detail.append("every other week") }
            detail.append(term.name)
            return .success(PreviewInfo(
                symbol: draft.kind.symbolName,
                title: "New course · \(name)",
                detail: detail.joined(separator: " · "),
                footnote: draft.location.isEmpty ? nil : draft.location
            ))

        case .event(let draft):
            let name = trimmed(draft.title)
            guard !name.isEmpty else { return .failure(.invalid("Add a title")) }
            return .success(PreviewInfo(
                symbol: draft.kind.symbolName,
                title: "New event · \(name)",
                detail: "\(dayLabel(draft.day)) · \(times(draft))",
                footnote: draft.location.isEmpty ? nil : draft.location
            ))

        case .todo(let draft):
            let name = trimmed(draft.title)
            guard !name.isEmpty else { return .failure(.invalid("Add a title")) }
            return .success(PreviewInfo(
                symbol: "checkmark.circle",
                title: "New todo · \(name)",
                detail: "\(scope(draft)) · P\(clampedPriority(draft.priority))",
                footnote: projectFootnote(draft.projectName)
            ))

        case .blackout(let draft):
            guard let term = currentTerm() else { return .failure(.noCurrentTerm) }
            let days = term.weeks.days(inWeeks: weekRange(draft))
            var footnote = trimmed(draft.reason)
            footnote = footnote.isEmpty ? term.name : "\(footnote) · \(term.name)"
            return .success(PreviewInfo(
                symbol: "eye.slash",
                title: "Clear \(kindsLabel(draft.kinds))",
                detail: "\(weeksLabel(weekRange(draft))) · \(dayLabel(days.lowerBound)) – \(dayLabel(days.upperBound))",
                footnote: footnote
            ))

        case .navigate(.today):
            return .success(PreviewInfo(symbol: "sun.max", title: "Go to Today", detail: dayLabel(today), footnote: nil))

        case .navigate(.week(let n)):
            guard let term = currentTerm() else { return .failure(.noCurrentTerm) }
            let days = term.weeks.days(inWeek: n)
            return .success(PreviewInfo(
                symbol: "calendar",
                title: "Go to week \(n)",
                detail: "\(dayLabel(days.lowerBound)) – \(dayLabel(days.upperBound))",
                footnote: term.name
            ))

        case .navigate(.section(let name)):
            guard let section = AppSection(rawValue: name) else { return .failure(.invalid("No section named “\(name)”")) }
            return .success(PreviewInfo(
                symbol: section.symbolName,
                title: "Go to \(section.title)",
                detail: "Switch section",
                footnote: nil
            ))
        }
    }

    // MARK: Execute

    /// Inserts the models `command` describes, or navigates. Throws whatever `preview` rejected.
    @discardableResult
    func execute(_ command: ParsedCommand) throws -> ExecutionResult {
        if case .failure(let error) = preview(command) { throw error }

        switch command {
        case .course(let draft):
            guard let term = currentTerm() else { throw ExecutionError.noCurrentTerm }
            let weeks = weekBounds(draft, in: term)
            let series = Series(
                title: trimmed(draft.title),
                kind: draft.kind,
                weekdays: draft.weekdays,
                startMinute: draft.startMinute,
                endMinute: draft.endMinute,
                intervalWeeks: draft.intervalWeeks,
                startWeek: weeks.start,
                endWeek: weeks.end,
                location: draft.location
            )
            context.insert(series)
            series.term = term
            appState.weekStart = term.contains(today) ? today.weekStart : term.weeks.weekStart(ofWeek: weeks.start)
            return ExecutionResult(
                message: "Added \(series.title) · \(schedule(draft)) · \(weeksLabel(weeks))",
                section: .week
            )

        case .event(let draft):
            let allDay = draft.startMinute == nil
            let start = draft.startMinute.map { WeekMath.instant(day: draft.day, minute: $0) } ?? draft.day.startDate()
            let end = draft.startMinute.map { WeekMath.instant(day: draft.day, minute: draft.endMinute ?? $0 + 60) } ?? start
            let event = Event(
                title: trimmed(draft.title),
                kind: draft.kind,
                start: start,
                end: end,
                isAllDay: allDay,
                location: draft.location
            )
            context.insert(event)
            appState.show(day: draft.day)
            return ExecutionResult(
                message: "Added \(event.title) · \(dayLabel(draft.day)) · \(times(draft))",
                section: .today
            )

        case .todo(let draft):
            let match = draft.projectName.flatMap(project(named:))
            let todo = TodoItem(
                title: trimmed(draft.title),
                priority: clampedPriority(draft.priority),
                day: draft.day,
                week: draft.week,
                project: match
            )
            context.insert(todo)
            var message = "Added \(todo.title) · \(scope(draft))"
            if let name = draft.projectName {
                message += match.map { " · \($0.title)" } ?? " · no project named \(name)"
            }
            return ExecutionResult(message: message, section: nil)

        case .blackout(let draft):
            guard let term = currentTerm() else { throw ExecutionError.noCurrentTerm }
            let days = term.weeks.days(inWeeks: weekRange(draft))
            context.insert(Blackout(
                start: days.lowerBound,
                end: days.upperBound,
                kinds: draft.kinds,
                reason: trimmed(draft.reason),
                term: term
            ))
            appState.weekStart = term.weeks.weekStart(ofWeek: weekRange(draft).lowerBound)
            return ExecutionResult(
                message: "Cleared \(kindsLabel(draft.kinds)) · \(weeksLabel(weekRange(draft)))",
                section: .week
            )

        case .navigate(.today):
            appState.goToToday()
            return ExecutionResult(message: "Today", section: nil)

        case .navigate(.week(let n)):
            guard let term = currentTerm() else { throw ExecutionError.noCurrentTerm }
            appState.weekStart = term.weeks.weekStart(ofWeek: n)
            return ExecutionResult(message: "Week \(n)", section: .week)

        case .navigate(.section(let name)):
            guard let section = AppSection(rawValue: name) else { throw ExecutionError.invalid("No section named “\(name)”") }
            return ExecutionResult(message: section.title, section: section)
        }
    }

    // MARK: Store lookups

    private func currentTerm() -> Term? { context.currentTerm(on: today) }

    private func projects() -> [Project] {
        (try? context.fetch(FetchDescriptor<Project>())) ?? []
    }

    private func project(named name: String) -> Project? {
        projects().first { $0.title.lowercased() == name.lowercased() }
    }

    private func projectFootnote(_ name: String?) -> String? {
        guard let name else { return nil }
        return project(named: name).map(\.title) ?? "no project named \(name)"
    }

    // MARK: Labels

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func clampedPriority(_ p: Int) -> Int { min(4, max(1, p)) }

    private func weekBounds(_ draft: CourseDraft, in term: Term) -> (start: Int, end: Int) {
        let start = draft.startWeek ?? 1
        return (start, max(start, draft.endWeek ?? term.weekCount))
    }

    private func weekRange(_ draft: BlackoutDraft) -> ClosedRange<Int> {
        min(draft.startWeek, draft.endWeek)...max(draft.startWeek, draft.endWeek)
    }

    private func weeksLabel(_ weeks: (start: Int, end: Int)) -> String {
        weeks.start == weeks.end ? "week \(weeks.start)" : "weeks \(weeks.start)–\(weeks.end)"
    }

    private func weeksLabel(_ weeks: ClosedRange<Int>) -> String {
        weeksLabel((weeks.lowerBound, weeks.upperBound))
    }

    private func schedule(_ draft: CourseDraft) -> String {
        let days = draft.weekdays.sorted().map(\.shortName).joined(separator: "/")
        return "\(days) \(WeekMath.timeLabel(minute: draft.startMinute))–\(WeekMath.timeLabel(minute: draft.endMinute))"
    }

    private func times(_ draft: EventDraft) -> String {
        guard let start = draft.startMinute else { return "all day" }
        let end = draft.endMinute ?? start + 60
        return "\(WeekMath.timeLabel(minute: start))–\(WeekMath.timeLabel(minute: end))"
    }

    private func scope(_ draft: TodoDraft) -> String {
        if let day = draft.day { return dayLabel(day) }
        if let week = draft.week { return "week of \(dayLabel(week))" }
        return "Someday"
    }

    private func kindsLabel(_ kinds: Set<Kind>) -> String {
        guard !kinds.isEmpty else { return "everything" }
        return kinds.sorted { $0.rawValue < $1.rawValue }.map { $0.pluralName.lowercased() }.joined(separator: ", ")
    }

    /// "Tue Sep 15". Built from the day key so it does not shift with the host's locale.
    private func dayLabel(_ day: DayKey) -> String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let c = day.civil
        return "\(day.weekday.shortName) \(months[c.month - 1]) \(c.day)"
    }
}
