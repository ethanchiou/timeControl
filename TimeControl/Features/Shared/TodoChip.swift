import SwiftData
import SwiftUI
import TimeControlCore

/// A task on the calendar. Tasks reach the calendar by their due date, so a chip is always an
/// all-day item: a priority dot, the title, and a tap that completes it in place — the same
/// direct-to-model interaction `TodoRow` uses. Editing needs a sheet, so that goes back to the caller.
struct TodoChip: View {
    let todo: TodoItem
    var height: CGFloat = 18
    var onEdit: (TodoItem) -> Void

    @Environment(\.modelContext) private var modelContext

    private var priority: Priority { Priority(clamping: todo.priority) }
    private var color: Color { todo.isDone ? .secondary : priority.color }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 6) }

    var body: some View {
        Button {
            withAnimation(.snappy) { todo.setDone(!todo.isDone) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 9))
                    .foregroundStyle(color)
                Text(todo.title)
                    .font(.caption2.weight(.medium))
                    .strikethrough(todo.isDone)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(color.opacity(todo.isDone ? 0.08 : 0.16))
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .frame(height: height)
        .help(helpText)
        .accessibilityLabel("\(todo.title), due \(dueText). \(todo.isDone ? "Done" : "Not done")")
        .contextMenu {
            Button(todo.isDone ? "Mark Not Done" : "Mark Done") {
                todo.setDone(!todo.isDone)
            }
            // The chip is placed by its due date, so the menu moves that — `ScheduleMenuItems`
            // moves the work-on bucket instead, which would leave the chip sitting where it was.
            Menu("Due") {
                Button("Today", systemImage: "sun.max") { setDue(.today()) }
                Button("Tomorrow", systemImage: "sunrise") { setDue(.today() + 1) }
                Button("Next Week", systemImage: "calendar.badge.plus") { setDue(.today() + 7) }
                Divider()
                Button("Day Earlier", systemImage: "chevron.left") { nudgeDue(-1) }
                Button("Day Later", systemImage: "chevron.right") { nudgeDue(1) }
                Divider()
                Button("Clear Due Date", systemImage: "tray") { setDue(nil) }
                    .disabled(todo.dueDay == nil)
            }
            Button("Edit…") { onEdit(todo) }
            Divider()
            Button("Delete", role: .destructive) { modelContext.delete(todo) }
        }
    }

    private func setDue(_ day: DayKey?) {
        withAnimation(.snappy) { todo.dueDay = day }
    }

    private func nudgeDue(_ days: Int) {
        guard let due = todo.dueDay else { return }
        setDue(due + days)
    }

    private var dueText: String {
        todo.dueDay.map { $0.startDate().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? "no date"
    }

    private var helpText: String {
        let project = todo.project.map { " · \($0.title)" } ?? ""
        return "\(todo.title) · Due \(dueText)\(project)"
    }
}
