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

    @State private var position: Int? = 0

    private var axes: Axis.Set { axis == .horizontal ? .horizontal : .vertical }

    var body: some View {
        GeometryReader { geo in
            ScrollView(axes) {
                pages(size: geo.size)
                    .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $position, anchor: .center)
            .defaultScrollAnchor(.center)
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { _, phase, _ in
                // Commit only once the scroll has come to rest, so the snap-back never fights the
                // deceleration still in flight.
                guard phase == .idle, let settled = position, settled != 0 else { return }
                shift(settled)
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { position = 0 }
            }
        }
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
