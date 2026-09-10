import SwiftUI

/// Pages the calendar with a trackpad scroll or a swipe: three viewport-sized pages — previous,
/// current, next — with the current one centred.
///
/// Settling on a neighbour commits the move and silently recentres. Because page 0 then renders what
/// the neighbour was already showing, the recentre is invisible; without it the reader would walk off
/// the end after two swipes.
struct CalendarPager<Content: View>: View {
    /// Horizontal pages a day or a week, vertical pages a month.
    let axis: Axis
    /// Called with -1 or +1 once the reader has settled on a neighbouring page.
    let shift: (Int) -> Void
    @ViewBuilder var page: (Int) -> Content

    private var axes: Axis.Set { axis == .horizontal ? .horizontal : .vertical }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(axes) {
                    pages(size: geo.size)
                        .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .defaultScrollAnchor(.center)
                .scrollIndicators(.hidden)
                .onScrollPhaseChange { _, phase, context in
                    // Commit only once the scroll has come to rest, so the snap-back never fights the
                    // deceleration still in flight. The page is read off the geometry rather than a
                    // `scrollPosition(id:)` binding: that binding reads nil once the reader has
                    // scrolled, so it could never say which page was settled on, and the calendar
                    // stuck one page out with the header still naming the page before.
                    guard phase == .idle else { return }
                    let settled = Self.settledPage(geometry: context.geometry, axis: axis)
                    guard settled != 0 else { return }
                    shift(settled)
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { proxy.scrollTo(0, anchor: .center) }
                }
            }
        }
    }

    /// Which of the three pages the scroll view is resting on: -1, 0 or +1.
    static func settledPage(geometry: ScrollGeometry, axis: Axis) -> Int {
        let offset = axis == .horizontal ? geometry.contentOffset.x : geometry.contentOffset.y
        let length = axis == .horizontal ? geometry.containerSize.width : geometry.containerSize.height
        return settledPage(offset: offset, pageLength: length)
    }

    /// Each page is exactly one container long, so the offset in containers is the index of the page
    /// at the leading edge: 0, 1 or 2 for previous, current, next.
    static func settledPage(offset: CGFloat, pageLength: CGFloat) -> Int {
        guard pageLength > 0 else { return 0 }
        let index = Int((offset / pageLength).rounded())
        return min(1, max(-1, index - 1))
    }

    /// Each page is exactly the viewport, which is the stride `.paging` snaps by, and is clipped to
    /// it: a grid that lays itself out a hair wider would otherwise spill over the fold and show a
    /// slice of the neighbouring week down the edge.
    @ViewBuilder
    private func pages(size: CGSize) -> some View {
        if axis == .horizontal {
            HStack(spacing: 0) { pageViews(size: size) }
        } else {
            VStack(spacing: 0) { pageViews(size: size) }
        }
    }

    private func pageViews(size: CGSize) -> some View {
        ForEach(-1...1, id: \.self) { offset in
            page(offset)
                .frame(width: size.width, height: size.height)
                .clipped()
                .id(offset)
        }
    }
}
