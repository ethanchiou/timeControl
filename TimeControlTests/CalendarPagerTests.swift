import SwiftUI
import Testing
@testable import TimeControl

@Suite struct CalendarPagerTests {
    private typealias Pager = CalendarPager<EmptyView>

    /// Three pages of one container each: resting at the start is the previous page, one container
    /// in is the current one, two in is the next.
    @Test func settledPageIsTheOffsetInContainers() {
        #expect(Pager.settledPage(offset: 0, pageLength: 637) == -1)
        #expect(Pager.settledPage(offset: 637, pageLength: 637) == 0)
        #expect(Pager.settledPage(offset: 1274, pageLength: 637) == 1)
    }

    /// Paging can rest a hair off the exact stride; the nearest page wins.
    @Test func settledPageRoundsToTheNearestPage() {
        #expect(Pager.settledPage(offset: 1273.6, pageLength: 637) == 1)
        #expect(Pager.settledPage(offset: 640, pageLength: 637) == 0)
    }

    /// The first idle phase arrives before layout, with an empty container; overscroll never leaves
    /// the strip either.
    @Test func settledPageStaysWithinTheThreePages() {
        #expect(Pager.settledPage(offset: 0, pageLength: 0) == 0)
        #expect(Pager.settledPage(offset: -40, pageLength: 637) == -1)
        #expect(Pager.settledPage(offset: 2000, pageLength: 637) == 1)
    }
}
