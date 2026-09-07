import SwiftUI
import TimeControlCore
#if os(macOS)
import AppKit
#endif

/// Hour and half-hour rules behind a day grid. Each hour row carries its hour as a scroll anchor.
struct HourLines: View {
    let hours: ClosedRange<Int>
    let hourHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(hours.lowerBound..<hours.upperBound, id: \.self) { hour in
                ZStack(alignment: .top) {
                    Rectangle().fill(.quaternary).frame(height: 0.5)
                    Rectangle().fill(.quinary).frame(height: 0.5).offset(y: hourHeight / 2)
                }
                .frame(height: hourHeight, alignment: .top)
                .id(hour)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(.quaternary).frame(height: 0.5)
        }
    }
}

/// The hour labels down the gutter of a day grid, each sitting just above its rule.
struct HourGutterLabels: View {
    let hours: ClosedRange<Int>
    let hourHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
            ForEach(hours, id: \.self) { hour in
                Text(Self.label(for: hour))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .offset(x: -6, y: CGFloat(hour - hours.lowerBound) * hourHeight - 6)
            }
        }
    }

    static func label(for hour: Int) -> String {
        WeekMath.instant(day: DayKey.epoch + hour / 24, minute: (hour % 24) * 60)
            .formatted(.dateTime.hour())
    }
}

/// Width a day grid has to leave free down its trailing edge for the vertical scroll bar.
///
/// With "Show scroll bars: Always" (or a mouse attached) macOS gives a `ScrollView` a legacy scroller
/// that takes its width out of the content. A grid whose header row sits *outside* the scroll view has
/// to account for it: without this the scrolling half is wider than the frame it was given, which widens
/// the enclosing stack and leaves the headers half a scroller to the right of their own columns.
enum DayGridMetrics {
    static var verticalScrollerInset: CGFloat {
        #if os(macOS)
        NSScroller.preferredScrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            : 0
        #else
        0
        #endif
    }
}
