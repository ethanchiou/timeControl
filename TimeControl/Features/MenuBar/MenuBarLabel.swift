#if os(macOS)
import AppKit
import SwiftData
import SwiftUI
import TimeControlCore

/// What appears in the menu bar itself: a tiny progress ring (or a checkmark/empty glyph) plus a done/total count.
struct MenuBarLabel: View {
    @Query private var todos: [TodoItem]

    @State private var ringCache: [RingProgress: Image] = [:]

    private var today: DayKey { .today() }
    private var progress: RingProgress { RingMath.daily(todos.map(\.spec), on: today) }

    var body: some View {
        HStack(spacing: 4) {
            icon
            if progress.total > 0 {
                Text("\(progress.done)/\(progress.total)")
                    .monospacedDigit()
            }
        }
        .task(id: progress) {
            cacheRingIfNeeded()
        }
    }

    @ViewBuilder
    private var icon: some View {
        if progress.isEmpty {
            Image(systemName: "circle.dashed")
        } else if progress.isComplete {
            Image(systemName: "checkmark.circle.fill")
        } else {
            ringCache[progress] ?? Image(systemName: "circle.dashed")
        }
    }

    private func cacheRingIfNeeded() {
        guard !progress.isEmpty, !progress.isComplete, ringCache[progress] == nil else { return }
        ringCache[progress] = Self.renderRing(progress: progress)
    }

    private static func renderRing(progress: RingProgress) -> Image? {
        let renderer = ImageRenderer(content:
            RingBadge(progress: progress, size: 14, tint: .primary)
                .frame(width: 16, height: 16)
        )
        renderer.scale = 2
        guard let nsImage = renderer.nsImage else { return nil }
        nsImage.isTemplate = true
        return Image(nsImage: nsImage)
    }
}
#endif
