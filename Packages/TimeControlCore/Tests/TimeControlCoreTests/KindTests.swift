import Foundation
import Testing
@testable import TimeControlCore

@Suite struct KindTests {
    /// Two kinds sharing a colour makes a week of blocks unreadable, which is the whole job of the colour.
    @Test func everyKindHasItsOwnColour() {
        let colours = Kind.allCases.map(\.colorHex)
        #expect(Set(colours).count == Kind.allCases.count)
    }

    /// The raw values are persisted in `kindRaw` and in backup files: renaming one silently reads back
    /// as `.course` (`Kind(rawValue:) ?? .course`), so they are pinned here rather than in a comment.
    @Test func rawValuesAreStable() {
        #expect(Kind.allCases.map(\.rawValue) == [
            "course", "tutorial", "exam", "interview", "appointment", "personal", "other",
        ])
    }

    @Test func tutorialCarriesItsOwnNameAndReminder() {
        #expect(Kind.tutorial.displayName == "Tutorial")
        #expect(Kind.tutorial.pluralName == "Tutorials")
        #expect(Kind.tutorial.defaultReminderMinutes == 10)
    }
}
