import SwiftUI
import TimeControlCore

/// The app's colour palette and the row of swatches that picks from it.
///
/// `matching` offers a leading swatch for "whatever this thing's kind already uses", which leaves the
/// selection nil rather than freezing today's kind colour into the record: change the kind later and
/// the colour still follows. It carries the kind's own symbol so it reads as inherited rather than as
/// a second blue dot.
///
/// `inherited` is the same leading swatch for things a `Kind` does not describe — a group's own colour,
/// say — and is only consulted when `matching` is nil.
struct ColorSwatchRow: View {
    static let palette = ["#4F7CFF", "#A855F7", "#10B981", "#F59E0B", "#E5484D", "#06B6D4", "#EC4899", "#6B7280"]

    @Binding var selection: String?
    /// The kind to inherit from, or nil for a picker with no inherited option.
    var matching: Kind?
    /// A leading "follow this" swatch that is not a kind's. Ignored when `matching` is set.
    var inherited: (hex: String, symbol: String, label: String)?

    var body: some View {
        // Nine swatches only just fit a phone-width form row, so the row scrolls rather than clips.
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if let matching {
                    swatch(
                        matching.colorHex,
                        symbol: matching.symbolName,
                        label: "Match the kind",
                        isSelected: selection == nil
                    ) { selection = nil }
                } else if let inherited {
                    swatch(
                        inherited.hex,
                        symbol: inherited.symbol,
                        label: inherited.label,
                        isSelected: selection == nil
                    ) { selection = nil }
                }
                ForEach(Self.palette, id: \.self) { hex in
                    swatch(hex, symbol: nil, label: "Colour \(hex)", isSelected: selection == hex) { selection = hex }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func swatch(
        _ hex: String,
        symbol: String?,
        label: String,
        isSelected: Bool,
        select: @escaping () -> Void
    ) -> some View {
        Button(action: select) {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 28, height: 28)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    } else if let symbol {
                        Image(systemName: symbol)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
