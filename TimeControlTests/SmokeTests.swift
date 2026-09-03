import Testing
@testable import TimeControl

@Suite struct SmokeTests {
    @Test func appModuleLinks() {
        #expect(true)
    }

    /// The sidebar is `List(AppSection.allCases, selection:)`, which tags each row with
    /// `Element.ID`. If that stops being the section itself the selection binding silently never
    /// matches: every sidebar click becomes a no-op, with no warning and no crash.
    @Test func sidebarSelectionTagMatchesTheSectionType() {
        #expect(AppSection.ID.self == AppSection.self)
    }
}
