import Foundation
import SwiftData
import TimeControlCore

/// A realistic fixture for manual QA: one term, four courses, an exam-week blackout, events, projects and todos.
/// Idempotent: loading twice does nothing the second time.
enum SampleData {
    static let termName = "Fall 2026 (Sample)"

    static func isLoaded(in context: ModelContext) -> Bool {
        let name = termName
        let d = FetchDescriptor<Term>(predicate: #Predicate { $0.name == name })
        return ((try? context.fetchCount(d)) ?? 0) > 0
    }

    static func load(into context: ModelContext) {
        guard !isLoaded(in: context) else { return }
        let today = DayKey.today()

        // Term anchored so that "today" falls in week 3 (keeps the sample interesting whenever it is loaded).
        let termStart = today.weekStart - 14
        let term = Term(name: termName, start: termStart, end: termStart + 7 * 15 - 3)
        context.insert(term)

        func course(_ title: String, _ days: Set<Weekday>, _ start: Int, _ end: Int, interval: Int = 1, startWeek: Int = 1, endWeek: Int = 14, kind: Kind = .course, location: String) {
            let s = Series(title: title, kind: kind, weekdays: days, startMinute: start, endMinute: end, intervalWeeks: interval, startWeek: startWeek, endWeek: endWeek, location: location)
            context.insert(s)
            s.term = term
        }
        course("CS201 Data Structures", [.monday, .wednesday], 10 * 60, 11 * 60 + 30, location: "Hall B 204")
        course("MATH240 Linear Algebra", [.tuesday, .thursday], 9 * 60, 10 * 60 + 20, location: "Science 110")
        course("CS201 Lab", [.friday], 14 * 60, 16 * 60, interval: 2, startWeek: 2, location: "Lab 3")
        course("PHIL101 Ethics", [.tuesday, .thursday], 13 * 60, 14 * 60 + 15, location: "Arts 12")
        course("Gym", [.monday, .wednesday, .friday], 7 * 60, 8 * 60, kind: .personal, location: "Rec Center")

        let examWeeks = term.weeks.days(inWeeks: 8...9)
        context.insert(Blackout(start: examWeeks.lowerBound, end: examWeeks.upperBound, kinds: [.course], reason: "Midterm exams", term: term))

        func event(_ title: String, kind: Kind, dayOffset: Int, start: Int, minutes: Int, location: String = "", routine: Bool = false) {
            let day = today + dayOffset
            let e = Event(title: title, kind: kind, start: WeekMath.instant(day: day, minute: start), end: WeekMath.instant(day: day, minute: start + minutes), location: location, isRoutine: routine)
            context.insert(e)
        }
        event("Chess club", kind: .personal, dayOffset: 2, start: 18 * 60, minutes: 90, location: "Student Union", routine: true)
        event("Interview · Northwind Software", kind: .interview, dayOffset: 1, start: 15 * 60, minutes: 60, location: "Zoom")
        event("Dentist", kind: .appointment, dayOffset: 3, start: 8 * 60 + 30, minutes: 45, location: "Main St Dental")
        event("MATH240 Midterm", kind: .exam, dayOffset: 9, start: 9 * 60, minutes: 120, location: "Science 110")

        let thesis = Project(title: "Senior Thesis", summary: "Literature review and first draft by December.", priority: 1, targetDay: term.end, colorHex: "#A855F7", sortOrder: 0)
        let jobs = Project(title: "Job Hunt", summary: "Ten applications, two interviews.", priority: 2, targetDay: today + 45, colorHex: "#F59E0B", sortOrder: 1)
        let apartment = Project(title: "Apartment Move", summary: "Done last month.", priority: 3, colorHex: "#10B981", sortOrder: 2)
        apartment.status = .done
        context.insert(thesis)
        context.insert(jobs)
        context.insert(apartment)

        // `dueDay` is what puts a task on the calendar, so the fixture spreads a few across the month.
        func todo(_ title: String, priority: Int, day: DayKey? = nil, week: DayKey? = nil, dueDay: DayKey? = nil, project: Project? = nil, done: Bool = false) {
            let t = TodoItem(title: title, priority: priority, day: day, week: week, dueDay: dueDay, project: project)
            if done { t.setDone(true) }
            context.insert(t)
        }
        todo("Read chapter 4 for CS201", priority: 2, day: today, dueDay: today, done: true)
        todo("Problem set 3", priority: 1, day: today, dueDay: today + 2)
        todo("Email advisor about thesis topic", priority: 2, day: today, dueDay: today + 1, project: thesis)
        todo("Prep interview questions", priority: 1, day: today + 1, dueDay: today + 1, project: jobs)
        todo("Laundry", priority: 4, day: today - 1)
        todo("Outline literature review", priority: 2, week: today, dueDay: today + 6, project: thesis)
        todo("Apply to 3 postings", priority: 2, week: today, dueDay: today + 9, project: jobs)
        todo("Renew library books", priority: 3, week: today, dueDay: today - 2, done: true)
        todo("Draft chapter 1", priority: 1, dueDay: today + 21, project: thesis)
        todo("Update résumé", priority: 3, project: jobs, done: true)
        todo("Return moving boxes", priority: 4, project: apartment, done: true)
    }

    /// Deletes every record. Used by the developer menu and the backup importer.
    static func wipe(_ context: ModelContext) throws {
        try context.delete(model: OccurrenceException.self)
        try context.delete(model: Series.self)
        try context.delete(model: Blackout.self)
        try context.delete(model: Term.self)
        try context.delete(model: Event.self)
        try context.delete(model: TodoItem.self)
        try context.delete(model: Project.self)
        try context.save()
    }
}
