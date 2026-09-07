import Testing
@testable import TimeControl

@Suite struct TermGridMathTests {
    @Test func pointsBelowTheFirstRuleBecomeMinutes() {
        #expect(TermGridMath.minute(atY: 0, firstHour: 7, hourHeight: 56) == 7 * 60)
        #expect(TermGridMath.minute(atY: 56, firstHour: 7, hourHeight: 56) == 8 * 60)
        #expect(TermGridMath.minute(atY: 28, firstHour: 9, hourHeight: 56) == 9 * 60 + 30)
    }

    @Test func clickStartsOnTheHalfHourBelowIt() {
        let slot = TermGridMath.slot(forClickAt: 9 * 60 + 47)
        #expect(slot.start == 9 * 60 + 30)
        #expect(slot.end == 11 * 60)
    }

    @Test func clickNearMidnightStaysInsideTheDay() {
        let slot = TermGridMath.slot(forClickAt: 23 * 60 + 50)
        #expect(slot.start == 23 * 60 + 30)
        #expect(slot.end == 24 * 60)
        #expect(TermGridMath.slot(forClickAt: -10).start == 0)
    }

    @Test func dragCoversItsRangeInEitherDirection() {
        let down = TermGridMath.slot(dragFrom: 10 * 60 + 3, to: 11 * 60 + 22)
        #expect(down.start == 10 * 60)
        #expect(down.end == 11 * 60 + 15)
        let up = TermGridMath.slot(dragFrom: 11 * 60 + 22, to: 10 * 60 + 3)
        #expect(up.start == 10 * 60)
        #expect(up.end == 11 * 60 + 15)
    }

    @Test func tinyDragStillMakesTheMinimumSlot() {
        let slot = TermGridMath.slot(dragFrom: 600, to: 603)
        #expect(slot.end - slot.start == TermGridMath.minimumDuration)
        let late = TermGridMath.slot(dragFrom: 24 * 60 - 5, to: 24 * 60 + 40)
        #expect(late.end == 24 * 60)
        #expect(late.end - late.start >= TermGridMath.minimumDuration)
    }

    @Test func moveKeepsTheLengthAndSnaps() {
        let moved = TermGridMath.moved(start: 600, end: 690, by: 38)
        #expect(moved.start == 645)
        #expect(moved.end == 735)
        let tiny = TermGridMath.moved(start: 600, end: 690, by: 6)
        #expect(tiny.start == 600)
    }

    @Test func moveNeverLeavesTheDay() {
        let early = TermGridMath.moved(start: 30, end: 120, by: -200)
        #expect(early.start == 0 && early.end == 90)
        let late = TermGridMath.moved(start: 22 * 60, end: 23 * 60 + 30, by: 300)
        #expect(late.end == 24 * 60 && late.start == 22 * 60 + 30)
    }

    @Test func resizeSnapsAndRespectsTheMinimum() {
        #expect(TermGridMath.resized(start: 600, end: 690, by: 22) == 705)
        #expect(TermGridMath.resized(start: 600, end: 690, by: -400) == 615)
        #expect(TermGridMath.resized(start: 23 * 60, end: 23 * 60 + 30, by: 500) == 24 * 60)
    }

    @Test func horizontalDragPicksTheNearestColumn() {
        #expect(TermGridMath.column(from: 0, dx: 30, columnWidth: 100, count: 7) == 0)
        #expect(TermGridMath.column(from: 0, dx: 60, columnWidth: 100, count: 7) == 1)
        #expect(TermGridMath.column(from: 6, dx: 250, columnWidth: 100, count: 7) == 6)
        #expect(TermGridMath.column(from: 2, dx: -260, columnWidth: 100, count: 7) == 0)
    }
}
