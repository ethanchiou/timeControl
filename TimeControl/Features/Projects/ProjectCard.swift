import SwiftData
import SwiftUI
import TimeControlCore

/// Compact kanban-style card summarizing a project: color bar, title, priority, progress ring, next todo.
struct ProjectCard: View {
    let project: Project

    private var color: Color { Color(hex: project.colorHex) }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(project.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    trailingBadge
                }

                Text(project.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 12) {
                    RingView(progress: project.progress, lineWidth: 6, tint: color, label: .fraction)
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(doneCountText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(project.targetCountdown.text)
                            .font(.caption)
                            .foregroundStyle(project.targetCountdown.style)
                        nextTodoLine
                    }
                }
            }
            .padding(16)
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(project.status == .paused ? 0.7 : 1)
    }

    private var doneCountText: String {
        "\(project.progress.done) of \(project.progress.total) done"
    }

    @ViewBuilder
    private var nextTodoLine: some View {
        if project.progress.isComplete {
            Text("All done")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } else if let next = project.openTodos.first {
            Label(next.title, systemImage: "circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var trailingBadge: some View {
        switch project.status {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .paused:
            HStack(spacing: 6) {
                Text("Paused")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
                PriorityBadge(priority: project.priority)
            }
        case .active:
            PriorityBadge(priority: project.priority)
        }
    }
}

/// Countdown to a project's target date, shared by `ProjectCard` and `ProjectDetailView`.
extension Project {
    enum TargetCountdown {
        case none
        case dueToday
        case dueIn(Int)
        case overdueBy(Int)

        var text: String {
            switch self {
            case .none: "No target date"
            case .dueToday: "Due today"
            case .dueIn(let days): "Due in \(days) day\(days == 1 ? "" : "s")"
            case .overdueBy(let days): "\(days) day\(days == 1 ? "" : "s") overdue"
            }
        }

        var style: AnyShapeStyle {
            switch self {
            case .none: AnyShapeStyle(.tertiary)
            case .overdueBy: AnyShapeStyle(Color.red)
            case .dueToday, .dueIn: AnyShapeStyle(.secondary)
            }
        }
    }

    var targetCountdown: TargetCountdown {
        guard let targetDay else { return .none }
        let days = targetDay - DayKey.today()
        if days == 0 { return .dueToday }
        if days > 0 { return .dueIn(days) }
        return .overdueBy(-days)
    }
}
