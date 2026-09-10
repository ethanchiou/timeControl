import Testing
import TimeControlCore
@testable import TimeControl

@MainActor
@Suite struct AppStateTests {
    /// A month of course blocks reads as noise, so the eye starts closed there and open elsewhere.
    @Test func theMonthOpensFilteredAndTheOtherScalesDoNot() {
        let appState = AppState()
        appState.section = .calendar

        appState.calendarScale = .month
        #expect(appState.hidesRoutine)

        appState.calendarScale = .week
        #expect(!appState.hidesRoutine)

        appState.calendarScale = .day
        #expect(!appState.hidesRoutine)
    }

    /// Today shows one day, so its eye follows the day's setting rather than whatever the calendar
    /// was last left on.
    @Test func todayReadsTheDayFilterWhateverTheCalendarScaleIs() {
        let appState = AppState()
        appState.calendarScale = .month
        appState.section = .today
        #expect(!appState.hidesRoutine)
    }

    @Test func togglingTheEyeLeavesTheOtherScalesAlone() {
        let appState = AppState()
        appState.section = .calendar
        appState.calendarScale = .week
        appState.hidesRoutine = true

        appState.calendarScale = .month
        #expect(appState.hidesRoutine)
        appState.hidesRoutine = false

        appState.calendarScale = .week
        #expect(appState.hidesRoutine)
    }

    @Test func pickingAScaleOpensItOnToday() {
        let appState = AppState()
        appState.show(day: DayKey.today() + 40)

        appState.selectScale(.month)
        #expect(appState.calendarScale == .month)
        #expect(appState.selectedDay == DayKey.today())
        #expect(appState.weekStart == DayKey.today().weekStart)
    }

    @Test func theGoMenuOpensTheCalendarOnToday() {
        let appState = AppState()
        appState.show(day: DayKey.today() - 30)

        appState.showCalendar(.week)
        #expect(appState.section == .calendar)
        #expect(appState.weekStart == DayKey.today().weekStart)
    }

    /// Tapping a date in the month grid drops to that day; it must not bounce back to today.
    @Test func openingADayFromTheMonthGridKeepsThatDay() {
        let appState = AppState()
        let day = DayKey.today() + 12
        appState.show(day: day)
        appState.calendarScale = .day
        #expect(appState.selectedDay == day)
    }
}
