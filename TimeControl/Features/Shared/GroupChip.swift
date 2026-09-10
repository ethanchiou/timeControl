import SwiftUI
import TimeControlCore

/// A small capsule chip for a group event: the group's glyph plus its name, tinted with the
/// group's colour. Mirrors `KindBadge`'s pill style.
struct GroupChip: View {
    var name: String
    var colorHex: String

    private var tint: Color { Color(hex: colorHex) }

    var body: some View {
        HStack(spacing: 4) {
            GroupGlyph(colorHex: colorHex)
            Text(name)
                .font(.caption)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Just the group's glyph, tinted with its colour — for tight spaces that can't fit the chip's name.
struct GroupGlyph: View {
    var colorHex: String

    var body: some View {
        Image(systemName: "person.2.fill")
            .foregroundStyle(Color(hex: colorHex))
    }
}
