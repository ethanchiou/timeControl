import Foundation
import Testing
@testable import TimeControl

@Suite struct TodoOrderingTests {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    private var list: [UUID] { [a, b, c] }

    @Test func movingDownPutsTheTodoWhereItWasDropped() {
        #expect(TodoOrdering.moving(a, before: c, in: list) == [b, a, c])
        #expect(TodoOrdering.moving(a, before: b, in: list) == [a, b, c])
    }

    @Test func movingUpPutsTheTodoWhereItWasDropped() {
        #expect(TodoOrdering.moving(c, before: a, in: list) == [c, a, b])
        #expect(TodoOrdering.moving(b, before: a, in: list) == [b, a, c])
    }

    @Test func aNilTargetMeansTheEndOfTheList() {
        #expect(TodoOrdering.moving(a, before: nil, in: list) == [b, c, a])
        #expect(TodoOrdering.moving(c, before: nil, in: list) == [a, b, c])
    }

    @Test func droppingOntoItselfChangesNothing() {
        #expect(TodoOrdering.moving(a, before: a, in: list) == list)
        #expect(TodoOrdering.moving(b, before: b, in: list) == list)
    }

    @Test func aTodoDraggedInFromAnotherBucketIsInserted() {
        // `d` is not in the list: dropping it on `b` should place it, not silently vanish.
        #expect(TodoOrdering.moving(d, before: b, in: list) == [a, d, b, c])
        #expect(TodoOrdering.moving(d, before: nil, in: list) == [a, b, c, d])
    }

    @Test func anUnknownTargetAppendsRatherThanLosingTheTodo() {
        #expect(TodoOrdering.moving(a, before: d, in: list) == [b, c, a])
        #expect(TodoOrdering.moving(d, before: UUID(), in: list) == [a, b, c, d])
    }

    @Test func everyMoveKeepsTheListIntact() {
        for moved in [a, b, c, d] {
            for target in [a, b, c, d, nil] {
                let result = TodoOrdering.moving(moved, before: target, in: list)
                #expect(Set(result).count == result.count, "duplicated an entry")
                #expect(Set(list).isSubset(of: Set(result)), "dropped an entry")
                #expect(result.contains(moved) || moved == target, "lost the moved todo")
            }
        }
    }

    @Test func anEmptyListTakesTheFirstTodo() {
        #expect(TodoOrdering.moving(a, before: nil, in: []) == [a])
        #expect(TodoOrdering.moving(a, before: b, in: []) == [a])
    }
}
