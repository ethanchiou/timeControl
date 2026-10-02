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
            "course", "tutorial", "assignment", "exam", "interview", "appointment", "hangout", "personal", "other",
        ])
    }

    /// Assignments and hangouts are the tags group events get. An assignment is due, not attended, so
    /// its default reminder is the day before rather than the hour before.
    @Test func assignmentAndHangoutCarryTheirOwnNamesAndReminders() {
        #expect(Kind.assignment.displayName == "Assignment")
        #expect(Kind.assignment.pluralName == "Assignments")
        #expect(Kind.assignment.defaultReminderMinutes == 1440)
        #expect(Kind.hangout.displayName == "Hangout")
        #expect(Kind.hangout.pluralName == "Hangouts")
        #expect(Kind.hangout.defaultReminderMinutes == 30)
    }

    @Test func tutorialCarriesItsOwnNameAndReminder() {
        #expect(Kind.tutorial.displayName == "Tutorial")
        #expect(Kind.tutorial.pluralName == "Tutorials")
        #expect(Kind.tutorial.defaultReminderMinutes == 10)
    }
}
