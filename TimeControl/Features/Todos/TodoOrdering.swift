import Foundation

/// Where a dragged todo lands. Pure list arithmetic, no SwiftUI and no models, so the awkward cases —
/// dropping onto itself, onto a todo from another bucket, onto empty space — are unit tested.
enum TodoOrdering {
    /// `ids` with `moved` lifted out and put back directly before `target`, or at the end when
    /// `target` is nil.
    ///
    /// `moved` need not already be in `ids`: dragging in from another bucket inserts it. A `target`
    /// that is not in `ids` appends, and dropping something onto itself changes nothing.
    nonisolated static func moving(_ moved: UUID, before target: UUID?, in ids: [UUID]) -> [UUID] {
        guard moved != target else { return ids }
        var result = ids
        result.removeAll { $0 == moved }
        guard let target, let insertion = result.firstIndex(of: target) else { return result + [moved] }
        result.insert(moved, at: insertion)
        return result
    }
}
