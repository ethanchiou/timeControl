import SwiftUI
import TimeControlCore

/// How a completion ring colours itself: red while most of the list is still open, ramping through
/// orange and amber to green as it fills.
///
/// The ring is one solid colour at any moment, never a gradient, so nothing moves while you are just
/// looking at it — the only motion is the colour sliding along the ramp when something is ticked off.
enum RingPalette {
    /// Hue in turns, the unit `Color(hue:saturation:brightness:)` takes. 0 is red, a third is green.
    static let openHue = 0.0
    static let doneHue = 1.0 / 3.0

    private static let saturation = 0.82
    private static let brightness = 0.85

    /// The hue for a fraction complete, clamped to `0...1`.
    static func hue(for fraction: Double) -> Double {
        let clamped = min(1, max(0, fraction))
        return openHue + (doneHue - openHue) * clamped
    }

    /// A ring with nothing in it is not failing at anything, so an empty list stays neutral rather
    /// than opening at an alarming red.
    static func color(for progress: RingProgress) -> Color {
        guard !progress.isEmpty else { return .gray }
        return Color(hue: hue(for: progress.fraction), saturation: saturation, brightness: brightness)
    }
}
