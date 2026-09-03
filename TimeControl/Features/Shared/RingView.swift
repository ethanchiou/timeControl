import SwiftUI
import TimeControlCore

/// What text (if any) to show at the center of a `RingView`.
enum RingLabel {
    case fraction
    case percent
    case none
    case custom(String)
}

/// Circular track + trimmed fill shared by `RingView` and `RingBadge`.
private struct RingTrackFill: View {
    var progress: RingProgress
    var lineWidth: CGFloat
    var tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress.fraction)
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .foregroundStyle(tint)
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.5), value: progress.fraction)
                // Keyed on the colour, so a progress-tinted ring slides to its new shade when a todo
                // is ticked and sits perfectly still the rest of the time.
                .animation(.easeInOut(duration: 0.45), value: tint)
        }
    }
}

/// Activity-style progress ring. Caller sets the size with `.frame`.
struct RingView: View {
    var progress: RingProgress
    var lineWidth: CGFloat = 10
    var tint: Color = .accentColor
    var label: RingLabel = .fraction

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                RingTrackFill(progress: progress, lineWidth: lineWidth, tint: tint)
                centerContent(size: size)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(progress.done) of \(progress.total)")
    }

    @ViewBuilder
    private func centerContent(size: CGFloat) -> some View {
        if progress.isComplete {
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        } else if progress.isEmpty {
            Text("–")
                .font(.system(size: size * 0.28, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        } else {
            labelText
                .font(.system(size: size * 0.26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.horizontal, lineWidth)
        }
    }

    @ViewBuilder
    private var labelText: some View {
        switch label {
        case .fraction: Text("\(progress.done)/\(progress.total)")
        case .percent: Text("\(Int((progress.fraction * 100).rounded()))%")
        case .none: EmptyView()
        case .custom(let text): Text(text)
        }
    }
}

/// Tiny inline ring for rows, cards and the menu bar. No label.
struct RingBadge: View {
    var progress: RingProgress
    var size: CGFloat = 18
    var tint: Color = .accentColor

    var body: some View {
        ZStack {
            RingTrackFill(progress: progress, lineWidth: max(2, size * 0.16), tint: tint)
            if progress.isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(progress.done) of \(progress.total)")
    }
}

#Preview("Empty") {
    RingView(progress: RingProgress(done: 0, total: 0))
        .frame(width: 120, height: 120)
        .padding()
}

#Preview("Partial - Fraction") {
    RingView(progress: RingProgress(done: 2, total: 5), tint: .blue)
        .frame(width: 120, height: 120)
        .padding()
}

#Preview("Partial - Percent") {
    RingView(progress: RingProgress(done: 2, total: 5), tint: .purple, label: .percent)
        .frame(width: 120, height: 120)
        .padding()
}

#Preview("Complete") {
    RingView(progress: RingProgress(done: 5, total: 5), tint: .green)
        .frame(width: 120, height: 120)
        .padding()
}

#Preview("Badges") {
    HStack(spacing: 16) {
        RingBadge(progress: RingProgress(done: 0, total: 0))
        RingBadge(progress: RingProgress(done: 1, total: 4), tint: .orange)
        RingBadge(progress: RingProgress(done: 4, total: 4), tint: .green)
        RingBadge(progress: RingProgress(done: 3, total: 6), size: 32, tint: .blue)
    }
    .padding()
}
