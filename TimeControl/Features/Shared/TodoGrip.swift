import SwiftUI

/// The drag handle on a todo row: two columns of three dots, the shape people already know to grab.
/// Carrying the `.draggable` on this rather than on the whole row means a drag has to be deliberate,
/// so swiping and scrolling a list of todos never picks one up by accident.
struct TodoGrip: View {
    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 3) {
                    dot
                    dot
                }
            }
        }
        .foregroundStyle(.tertiary)
        // Comfortably grabbable with a finger without crowding the row's text.
        .frame(width: 28, height: 36)
        .contentShape(.rect)
        .help("Drag to reorder")
        .accessibilityLabel("Reorder")
    }

    private var dot: some View {
        Circle().frame(width: 3, height: 3)
    }
}
