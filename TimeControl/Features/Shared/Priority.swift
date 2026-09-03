import SwiftUI

/// Todo/project priority: 1 urgent … 4 low.
enum Priority: Int, CaseIterable, Identifiable, Sendable {
    case urgent = 1, high = 2, normal = 3, low = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .urgent: "Urgent"
        case .high: "High"
        case .normal: "Normal"
        case .low: "Low"
        }
    }

    var shortTitle: String { "P\(rawValue)" }

    /// System colors only.
    var color: Color {
        switch self {
        case .urgent: .red
        case .high: .orange
        case .normal: .blue
        case .low: .gray
        }
    }

    var symbolName: String {
        switch self {
        case .urgent: "exclamationmark.2"
        case .high: "exclamationmark"
        case .normal: "minus"
        case .low: "arrow.down"
        }
    }

    /// Clamps `raw` into `1...4`, defaulting to `.normal` if it lands out of range.
    init(clamping raw: Int) {
        self = Priority(rawValue: min(4, max(1, raw))) ?? .normal
    }
}

struct PriorityBadge: View {
    var priority: Int
    var compact: Bool = true

    private var resolved: Priority { Priority(clamping: priority) }

    var body: some View {
        if compact {
            Text(resolved.shortTitle)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(resolved.color.opacity(0.15), in: Capsule())
                .foregroundStyle(resolved.color)
        } else {
            Label(resolved.title, systemImage: resolved.symbolName)
                .font(.caption)
                .foregroundStyle(resolved.color)
        }
    }
}
