import Foundation
import Testing
import TimeControlCore
@testable import TimeControl

@MainActor
@Suite(.serialized) struct KindColorSettingsTests {
    private func reset() {
        KindColorSettings.applyRemote([:])
    }

    @Test func overrideWinsAndClearingReturnsToTheDefault() {
        reset()
        defer { reset() }
        #expect(KindColorSettings.hex(for: .assignment) == Kind.assignment.colorHex)
        KindColorSettings.set("#123456", for: .assignment)
        #expect(KindColorSettings.hex(for: .assignment) == "#123456")
        #expect(KindColorSettings.overrides == ["assignment": "#123456"])
        KindColorSettings.set(nil, for: .assignment)
        #expect(KindColorSettings.hex(for: .assignment) == Kind.assignment.colorHex)
        #expect(KindColorSettings.overrides.isEmpty)
    }

    @Test func theProfilesMapReplacesTheLocalOne() {
        reset()
        defer { reset() }
        KindColorSettings.set("#111111", for: .exam)
        KindColorSettings.applyRemote(["hangout": "#222222", "nonsense": "#333333"])
        #expect(KindColorSettings.override(for: .exam) == nil, "a kind missing from the profile is back on its default")
        #expect(KindColorSettings.hex(for: .hangout) == "#222222")
        #expect(KindColorSettings.overrides == ["hangout": "#222222"], "unknown kinds are ignored")
    }
}
