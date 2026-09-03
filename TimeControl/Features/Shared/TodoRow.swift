import SwiftData
import SwiftUI
import TimeControlCore

/// One todo line, usable inside List rows and plain stacks (menu bar). Toggles completion in place.
struct TodoRow: View {
    let todo: TodoItem
    var showsProject: Bool = true
    var showsDate: Bool = false

    private var priority: Priority { Priority(clamping: todo.priority) }

    /// The touch checkbox already carries its own padding, so the row tightens to compensate.
    #if os(macOS)
    private let rowSpacing: CGFloat = 10
    #else
    private let rowSpacing: CGFloat = 2
    #endif

    var body: some View {
        HStack(spacing: rowSpacing) {
            Button {
                withAnimation(.snappy) {
                    todo.setDone(!todo.isDone)
                }
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(todo.isDone ? Color.green : priority.color)
                    // Touch needs 44pt around the glyph; the Mac keeps the tight row it was designed with.
                    #if !os(macOS)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
                    #endif
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.isDone ? "Mark not done" : "Mark done")

            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title)
                    .font(.body)
                    .strikethrough(todo.isDone)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                    .lineLimit(2)

                if showsDate, let dateText {
                    Text(dateText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if priority != .normal {
                    PriorityBadge(priority: todo.priority)
                }
                if showsProject, let project = todo.project {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: project.colorHex))
                            .frame(width: 6, height: 6)
                        Text(project.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(minHeight: 32)
    }

    private var dateText: String? {
        if let day = todo.day {
            return day.startDate().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        if let week = todo.week {
            return "Week of \(week.startDate().formatted(.dateTime.month(.abbreviated).day()))"
        }
        return nil
    }
}

#Preview {
    let container = try! ModelContainerFactory.make(inMemory: true)
    let context = container.mainContext
    let project = Project(title: "Thesis", colorHex: "#4F7CFF")
    context.insert(project)
    let todo = TodoItem(title: "Read chapter 4 and outline the argument", priority: 1, day: .today(), project: project)
    context.insert(todo)
    return List {
        TodoRow(todo: todo, showsDate: true)
    }
    .modelContainer(container)
}
