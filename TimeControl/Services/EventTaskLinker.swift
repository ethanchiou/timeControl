import CryptoKit
import Foundation
import SwiftData
import TimeControlCore

/// Keeps one todo per non-routine event, so an assignment, exam or appointment sits in the day's
/// task list and counts in the ring like anything else you have to get done.
///
/// The todo is the member's completion record for the event: ticking it finishes the event for them
/// (and, for a shared-completion event, for everyone — see `TodoItem.setDone`). Its title and due day
/// follow the event; the day the member plans to work on it is theirs to move. Routine events (gym,
/// club) are habits, not tasks, and get none.
///
/// `reconcile` runs after every save and after every pull. It is idempotent and only saves when it
/// changed something, so the save it triggers never loops. It runs *tracked*: the todos it makes are
/// real rows that must reach the server, unlike the pulled rows that caused them.
@MainActor
enum EventTaskLinker {
    /// Namespace for the deterministic todo ids. Fixed forever: a different value would give every
    /// event a second todo on the next reconcile.
    static let namespace = UUID(uuidString: "5D2C8F1E-7A3B-4C6D-9E0F-1A2B3C4D5E6F")!

    /// The id of `userID`'s todo for `eventID`. Two devices of one account derive the same id, so
    /// both creating it offline still upserts one row. Without an account the id depends on the event
    /// alone; a personal event only ever has one owner, so that is still unique.
    static func todoID(forEvent eventID: UUID, userID: UUID?) -> UUID {
        uuid5(namespace, "\(eventID.uuidString.lowercased())|\(userID?.uuidString.lowercased() ?? "")")
    }

    /// Whether `event` should get a todo it does not have yet. Only from today on: back-filling months
    /// of past events would rewrite every historic ring. An event already tracked keeps its todo.
    static func wantsTodo(_ event: Event, today: DayKey) -> Bool {
        event.isCompletable && event.day >= today
    }

    /// Brings every linked todo in line with its event: drops todos whose event is gone or became
    /// routine, collapses duplicates, creates the missing ones and mirrors title, due day and shared
    /// completion. Returns whether anything changed.
    @discardableResult
    static func reconcile(in context: ModelContext, userID: UUID?, today: DayKey = .today()) -> Bool {
        guard let events = try? context.fetch(FetchDescriptor<Event>()),
              let todos = try? context.fetch(FetchDescriptor<TodoItem>()) else { return false }
        let eventsByID = Dictionary(events.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        var linked: [UUID: TodoItem] = [:]
        var changed = false

        for todo in todos {
            guard let eventID = todo.eventID else { continue }
            guard let event = eventsByID[eventID], event.isCompletable else {
                context.delete(todo)
                changed = true
                continue
            }
            if let other = linked[eventID] {
                // Two todos for one event, made on two devices before either had the other's. Keep
                // the older; a tick on the one being dropped is not lost.
                let (keep, drop) = other.createdAt <= todo.createdAt ? (other, todo) : (todo, other)
                if drop.isDone, !keep.isDone {
                    keep.isDone = true
                    keep.completedAt = drop.completedAt
                }
                context.delete(drop)
                linked[eventID] = keep
                changed = true
                continue
            }
            linked[eventID] = todo
        }

        for event in events {
            if let todo = linked[event.uuid] {
                if mirror(event, onto: todo) { changed = true }
            } else if wantsTodo(event, today: today) {
                let todo = TodoItem(title: event.title, priority: defaultPriority(for: event.kind), day: event.day, dueDay: event.day)
                todo.uuid = todoID(forEvent: event.uuid, userID: userID)
                todo.eventID = event.uuid
                context.insert(todo)
                mirror(event, onto: todo)
                changed = true
            }
        }

        if changed { try? context.save() }
        return changed
    }

    /// Title and due day follow the event. When the event moves, the work-on day moves with it only
    /// if it was still on the old due day; a member who pulled the work earlier keeps their plan. A
    /// shared-completion event's done state is the event's, whoever finished it.
    @discardableResult
    static func mirror(_ event: Event, onto todo: TodoItem) -> Bool {
        var changed = false
        if todo.title != event.title {
            todo.title = event.title
            changed = true
        }
        if todo.dueDay != event.day {
            if todo.day == todo.dueDay { todo.schedule(on: event.day) }
            todo.dueDay = event.day
            changed = true
        }
        if event.sharedCompletion {
            let done = event.completedAt != nil
            if todo.isDone != done {
                todo.isDone = done
                todo.completedAt = done ? event.completedAt : nil
                changed = true
            }
        }
        return changed
    }

    /// Exams outrank assignments outrank the rest, the way most students would file them.
    static func defaultPriority(for kind: Kind) -> Int {
        switch kind {
        case .exam: 1
        case .assignment, .interview: 2
        default: 3
        }
    }

    /// RFC 4122 version 5: SHA-1 of the namespace and the name, with the version and variant bits set.
    static func uuid5(_ namespace: UUID, _ name: String) -> UUID {
        var bytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        bytes += Array(name.utf8)
        var digest = Array(Insecure.SHA1.hash(data: bytes))
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]
        ))
    }
}

extension ModelContext {
    /// The signed-in user's todo for `eventID`, if the linker has made one.
    func linkedTodo(forEvent eventID: UUID) -> TodoItem? {
        var d = FetchDescriptor<TodoItem>(predicate: #Predicate { $0.eventID == eventID })
        d.fetchLimit = 1
        return try? fetch(d).first
    }

    /// Finishes or reopens an event the way its linked todo would: through the todo when there is
    /// one (so the ring moves), else on the event itself when the group shares completion.
    func setEventDone(_ eventID: UUID, _ done: Bool) {
        if let todo = linkedTodo(forEvent: eventID) {
            todo.setDone(done)
        } else if let event = event(uuid: eventID), event.sharedCompletion {
            event.setCompleted(done, by: AuthService.shared.userID)
        }
    }
}
