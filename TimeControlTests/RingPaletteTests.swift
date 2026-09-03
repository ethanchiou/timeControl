import Testing
import TimeControlCore
@testable import TimeControl

@Suite struct RingPaletteTests {
    @Test func rampRunsFromRedToGreen() {
        #expect(RingPalette.hue(for: 0) == RingPalette.openHue)
        #expect(RingPalette.hue(for: 1) == RingPalette.doneHue)
        // Red is hue 0 and green a third of the way round; the ramp between is orange and amber.
        #expect(RingPalette.openHue == 0)
        #expect(abs(RingPalette.doneHue - 1.0 / 3.0) < 1e-12)
    }

    @Test func rampIsMonotonicAndStaysInTheWarmToGreenArc() {
        var previous = -1.0
        for step in 0...20 {
            let hue = RingPalette.hue(for: Double(step) / 20)
            #expect(hue > previous, "\(step)")
            #expect(hue >= RingPalette.openHue && hue <= RingPalette.doneHue, "\(step)")
            previous = hue
        }
        // Half done is amber: past orange, not yet green.
        let half = RingPalette.hue(for: 0.5)
        #expect(half > 0.1 && half < 0.2)
    }

    @Test func fractionsOutsideZeroToOneClamp() {
        #expect(RingPalette.hue(for: -3) == RingPalette.openHue)
        #expect(RingPalette.hue(for: 4) == RingPalette.doneHue)
        #expect(RingPalette.hue(for: .infinity) == RingPalette.doneHue)
    }

    @Test func aFinishedListIsGreenAndAnEmptyOneIsNeutral() {
        // RingProgress clamps done into 0...total, so these are the real end states.
        #expect(RingPalette.hue(for: RingProgress(done: 5, total: 5).fraction) == RingPalette.doneHue)
        #expect(RingPalette.hue(for: RingProgress(done: 0, total: 5).fraction) == RingPalette.openHue)
        // Nothing planned is not failure: it stays grey rather than opening at red.
        #expect(RingPalette.color(for: .empty) == .gray)
        #expect(RingPalette.color(for: RingProgress(done: 0, total: 4)) != .gray)
    }
}
