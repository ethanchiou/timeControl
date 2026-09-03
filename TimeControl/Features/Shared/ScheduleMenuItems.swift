import SwiftUI
import TimeControlCore

/// Buttons that move a todo between buckets. Drop into a `Menu("Schedule") { … }` or a `.contextMenu`.
struct ScheduleMenuItems: View {
    let todo: TodoItem

    var body: some View {
        let today = DayKey.today()
        Button("Today", systemImage: "sun.max") { move { $0.schedule(on: today) } }
        Button("Tomorrow", systemImage: "sunrise") { move { $0.schedule(on: today + 1) } }
        Button("This Week", systemImage: "calendar") { move { $0.schedule(inWeekOf: today) } }
        Button("Next Week", systemImage: "calendar.badge.plus") { move { $0.schedule(inWeekOf: today + 7) } }
        Divider()
        Button("Unschedule", systemImage: "tray") { move { $0.unschedule() } }
            .disabled(todo.day == nil && todo.week == nil)
    }

    private func move(_ change: (TodoItem) -> Void) {
        withAnimation(.snappy) { change(todo) }
    }
}
