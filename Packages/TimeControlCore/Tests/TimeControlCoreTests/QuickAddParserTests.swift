import Foundation
import Testing
@testable import TimeControlCore

private extension ParsedCommand {
    var asCourse: CourseDraft? { if case .course(let c) = self { return c } else { return nil } }
    var asEvent: EventDraft? { if case .event(let e) = self { return e } else { return nil } }
    var asTodo: TodoDraft? { if case .todo(let t) = self { return t } else { return nil } }
    var asBlackout: BlackoutDraft? { if case .blackout(let b) = self { return b } else { return nil } }
    var asNavigation: Navigation? { if case .navigate(let n) = self { return n } else { return nil } }
}

@Suite struct QuickAddParserTests {
    let la = Calendar.app(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

    /// Wednesday 2026-09-09. The week's Monday is Sep 7.
    var context: QuickAddContext {
        QuickAddContext(today: d(9, 9), calendar: la, projectNames: ["Thesis", "Job Hunt"], hasCurrentTerm: true)
    }

    var termless: QuickAddContext {
        QuickAddContext(today: d(9, 9), calendar: la, projectNames: ["Thesis", "Job Hunt"], hasCurrentTerm: false)
    }

    func d(_ m: Int, _ day: Int) -> DayKey { DayKey(year: 2026, month: m, day: day) }

    func p(_ s: String, forcing: CommandType? = nil, in ctx: QuickAddContext? = nil) -> ParsedCommand? {
        QuickAddParser.parse(s, context: ctx ?? context, forcing: forcing)
    }

    // MARK: Blank input

    @Test func blankInputIsNil() {
        #expect(p("") == nil)
        #expect(p("   ") == nil)
        #expect(p("\n\t ") == nil)
    }

    // MARK: Navigation

    @Test func todayAloneNavigates() {
        #expect(p("today")?.asNavigation == .today)
        #expect(p("Today")?.asNavigation == .today)
        #expect(p("today")?.type == nil)
    }

    @Test func weekNumbersNavigate() {
        #expect(p("week 7")?.asNavigation == .week(7))
        #expect(p("wk 7")?.asNavigation == .week(7))
        #expect(p("w7")?.asNavigation == .week(7))
        #expect(p("WEEK 12")?.asNavigation == .week(12))
    }

    @Test func goOpenShowNavigateToSections() {
        #expect(p("go projects")?.asNavigation == .section("projects"))
        #expect(p("open todos")?.asNavigation == .section("todos"))
        #expect(p("show settings")?.asNavigation == .section("settings"))
        #expect(p("go terms")?.asNavigation == .section("terms"))
        #expect(p("go week")?.asNavigation == .section("week"))
        #expect(p("go today")?.asNavigation == .section("today"))
        #expect(p("go to projects")?.asNavigation == .section("projects"))
    }

    @Test func commandsOnlyWinWhenTheyAreTheWholeInput() {
        let todo = p("Call mom today")?.asTodo
        #expect(todo?.title == "Call mom")
        #expect(todo?.day == d(9, 9))
        // "week 7 planning" is not navigation.
        #expect(p("week 7 planning")?.asNavigation == nil)
    }

    // MARK: Blackouts

    @Test func clearCoursesForAWeekRangeWithAReason() {
        let b = p("clear courses weeks 8-9 fall break")?.asBlackout
        #expect(b?.kinds == [.course])
        #expect(b?.startWeek == 8)
        #expect(b?.endWeek == 9)
        #expect(b?.reason == "fall break")
    }

    @Test func clearAcceptsSeveralKindsAndASingleWeek() {
        let b = p("clear exams and courses week 8")?.asBlackout
        #expect(b?.kinds == [.exam, .course])
        #expect(b?.startWeek == 8)
        #expect(b?.endWeek == 8)
        #expect(b?.reason == "")
    }

    @Test func clearAllMeansEveryKind() {
        let b = p("clear all weeks 8-9")?.asBlackout
        #expect(b?.kinds.isEmpty == true)
        #expect(b?.startWeek == 8 && b?.endWeek == 9)
        #expect(p("clear everything week 3")?.asBlackout?.kinds.isEmpty == true)
    }

    @Test func hideIsASynonymAndEnDashesWork() {
        let b = p("hide courses wk 8–9")?.asBlackout
        #expect(b?.kinds == [.course])
        #expect(b?.startWeek == 8 && b?.endWeek == 9)
        #expect(p("hide courses wk 8–9")?.type == nil)
    }

    @Test func clearWithoutAWeekIsNotABlackout() {
        #expect(p("Clear my desk")?.asTodo?.title == "Clear my desk")
    }

    // MARK: Courses

    @Test func weekdayCodesPlusRangePlusLocationPlusWeeks() {
        let c = p("CS201 MWF 10-11 @Wean 5409 weeks 1-14")?.asCourse
        #expect(c?.title == "CS201")
        #expect(c?.kind == .course)
        #expect(c?.weekdays == [.monday, .wednesday, .friday])
        #expect(c?.startMinute == 600)
        #expect(c?.endMinute == 660)
        #expect(c?.location == "Wean 5409")
        #expect(c?.startWeek == 1)
        #expect(c?.endWeek == 14)
        #expect(c?.intervalWeeks == 1)
    }

    @Test func slashSeparatedNamesAndTwentyFourHourEnDashRange() {
        let c = p("Physics Mon/Wed 14:00–15:30")?.asCourse
        #expect(c?.weekdays == [.monday, .wednesday])
        #expect(c?.startMinute == 840)
        #expect(c?.endMinute == 930)
        #expect(c?.startWeek == nil && c?.endWeek == nil)
    }

    @Test func tuThCodeWithTrailingPmAppliedToBothEnds() {
        let c = p("Bio TuTh 1-2:30pm biweekly")?.asCourse
        #expect(c?.weekdays == [.tuesday, .thursday])
        #expect(c?.startMinute == 780)
        #expect(c?.endMinute == 870)
        #expect(c?.intervalWeeks == 2)
    }

    @Test func spelledOutWeekdaysJoinedByAndWithAToRange() {
        let c = p("Seminar Monday and Wednesday 10 to 11:30")?.asCourse
        #expect(c?.weekdays == [.monday, .wednesday])
        #expect(c?.startMinute == 600)
        #expect(c?.endMinute == 690)
        #expect(c?.title == "Seminar")
    }

    @Test func singleWeekdayWithARangeAndAWeekWindowIsACourse() {
        let c = p("Lab Fri 9-10 weeks 3 to 10")?.asCourse
        #expect(c?.weekdays == [.friday])
        #expect(c?.startMinute == 540)
        #expect(c?.endMinute == 600)
        #expect(c?.startWeek == 3)
        #expect(c?.endWeek == 10)
    }

    @Test func plusSeparatorAndEveryOtherWeek() {
        let c = p("Stats Tue+Thu 10am-11:30am every other week")?.asCourse
        #expect(c?.weekdays == [.tuesday, .thursday])
        #expect(c?.startMinute == 600)
        #expect(c?.endMinute == 690)
        #expect(c?.intervalWeeks == 2)
    }

    @Test func singleLetterCodesSeparatedBySlashes() {
        let c = p("Calculus M/W/F 9-10")?.asCourse
        #expect(c?.weekdays == [.monday, .wednesday, .friday])
        #expect(c?.startMinute == 540 && c?.endMinute == 600)
    }

    @Test func commaSeparatedWeekdaysAndFortnightly() {
        let c = p("Studio Mon, Wed 3-5pm fortnightly")?.asCourse
        #expect(c?.weekdays == [.monday, .wednesday])
        #expect(c?.startMinute == 900)
        #expect(c?.endMinute == 1020)
        #expect(c?.intervalWeeks == 2)
    }

    @Test func kindTagOverridesTheCourseKind() {
        let c = p("Review MW 10-11 #exam")?.asCourse
        #expect(c?.kind == .exam)
        #expect(c?.title == "Review")
        #expect(p("Review MW 10-11 #exam")?.type == .course)
    }

    @Test func gluedWeekTokenSetsTheWindow() {
        let c = p("Colloquium Thu 4-5pm w2-12")?.asCourse
        #expect(c?.startWeek == 2 && c?.endWeek == 12)
        #expect(c?.startMinute == 960 && c?.endMinute == 1020)
    }

    @Test func withoutATermCourseShapedInputFallsThroughToAnEvent() {
        let cmd = p("CS201 MWF 10-11", in: termless)
        #expect(cmd?.asCourse == nil)
        let e = cmd?.asEvent
        #expect(e?.title == "CS201")
        #expect(e?.day == d(9, 9))          // today is a Wednesday, the soonest of M/W/F
        #expect(e?.startMinute == 600 && e?.endMinute == 660)
    }

    // MARK: Events

    @Test func weekdayPlusSingleTimeIsAnEvent() {
        let e = p("Interview Tue 3pm")?.asEvent
        #expect(e?.title == "Interview")
        #expect(e?.kind == .interview)
        #expect(e?.day == d(9, 15))
        #expect(e?.startMinute == 900)
        #expect(e?.endMinute == nil)        // caller applies the 60 minute default
    }

    @Test func aWeekdayNameResolvesToTodayWhenItIsToday() {
        let e = p("Interview Wed 9am")?.asEvent
        #expect(e?.day == d(9, 9))
    }

    @Test func nextWeekdaySkipsToTheFollowingWeek() {
        let e = p("Haircut next Wed 4pm")?.asEvent
        #expect(e?.day == d(9, 16))
        #expect(e?.kind == .appointment)
        #expect(e?.startMinute == 960)
    }

    @Test func weekdayAloneWithAnEventishTitleIsAnAllDayEvent() {
        let e = p("Dentist Tue")?.asEvent
        #expect(e?.kind == .appointment)
        #expect(e?.day == d(9, 15))
        #expect(e?.startMinute == nil)
        #expect(e?.title == "Dentist")
    }

    @Test func tomorrowWithATwentyFourHourTime() {
        let e = p("Lunch tomorrow 12:30")?.asEvent
        #expect(e?.day == d(9, 10))
        #expect(e?.startMinute == 750)
        #expect(e?.kind == .other)
        #expect(p("Lunch tmr 12:30")?.asEvent?.day == d(9, 10))
    }

    @Test func monthNameAndDayWithABareAtTime() {
        let e = p("Meeting Sep 14 at 3")?.asEvent
        #expect(e?.day == d(9, 14))
        #expect(e?.startMinute == 900)      // bare 3 reads as pm
        #expect(e?.kind == .appointment)
        #expect(e?.title == "Meeting")
    }

    @Test func dayThenMonthWithALocation() {
        let e = p("Interview 14 Sep 2pm @Zoom")?.asEvent
        #expect(e?.day == d(9, 14))
        #expect(e?.startMinute == 840)
        #expect(e?.location == "Zoom")
        #expect(e?.title == "Interview")
    }

    @Test func fullMonthNameWithNoTimeIsAllDay() {
        let e = p("Doctor September 14")?.asEvent
        #expect(e?.day == d(9, 14))
        #expect(e?.startMinute == nil)
        #expect(e?.kind == .appointment)
    }

    @Test func slashDatesUseTheContextYear() {
        let e = p("Quiz 9/14 10am")?.asEvent
        #expect(e?.day == d(9, 14))
        #expect(e?.startMinute == 600)
        #expect(e?.kind == .exam)
    }

    @Test func isoDatesParse() {
        let e = p("Concert 2026-09-14 7pm")?.asEvent
        #expect(e?.day == d(9, 14))
        #expect(e?.startMinute == 1140)
        #expect(e?.kind == .other)
    }

    @Test func durationsProduceAnEndMinute() {
        #expect(p("Standup Thu 3pm for 1h")?.asEvent?.endMinute == 960)
        #expect(p("Sync Thu 3pm for 90m")?.asEvent?.endMinute == 990)
        #expect(p("Sync Thu 3pm for 1h30")?.asEvent?.endMinute == 990)
        #expect(p("Sync Thu 3pm for 2 hours")?.asEvent?.endMinute == 1020)
        #expect(p("Sync Thu 3pm for 1h")?.asEvent?.startMinute == 900)
    }

    @Test func explicitKindTagPlusADateMakesAnEvent() {
        let e = p("Coffee tomorrow #personal")?.asEvent
        #expect(e?.kind == .personal)
        #expect(e?.day == d(9, 10))
        #expect(e?.title == "Coffee")
    }

    @Test func kindIsInferredFromTitleWords() {
        #expect(p("Midterm today")?.asEvent?.kind == .exam)
        #expect(p("Final today")?.asEvent?.kind == .exam)
        #expect(p("Phone interview today")?.asEvent?.kind == .interview)
        #expect(p("Team meeting today")?.asEvent?.kind == .appointment)
        #expect(p("Haircut today")?.asEvent?.kind == .appointment)
    }

    @Test func timeRangesOnEventsSurviveWhenThereIsNoWeekday() {
        let e = p("Orientation Sep 14 9-10:30am")?.asEvent
        #expect(e?.day == d(9, 14))
        #expect(e?.startMinute == 540)
        #expect(e?.endMinute == 630)
    }

    @Test func aLoneWeekdayPlusARangeIsAnEventWhenTheTitleSoundsLikeOne() {
        // Rule 2 needs more than one weekday, a weeks/interval token, a kind tag, or a neutral title.
        let e = p("Interview Tue 3-4pm")?.asEvent
        #expect(p("Interview Tue 3-4pm")?.asCourse == nil)
        #expect(e?.kind == .interview)
        #expect(e?.day == d(9, 15))
        #expect(e?.startMinute == 900)
        #expect(e?.endMinute == 960)
        #expect(e?.title == "Interview")
    }

    @Test func aLoneWeekdayPlusARangeStaysACourseOnANeutralTitle() {
        let c = p("CS201 Fri 10-11:30")?.asCourse
        #expect(c?.weekdays == [.friday])
        #expect(c?.startMinute == 600)
        #expect(c?.endMinute == 690)
        #expect(c?.title == "CS201")
        // A second weekday, a weeks window, an interval token or a kind tag each restore the course reading.
        #expect(p("Interview Tue Thu 3-4pm")?.type == .course)
        #expect(p("Interview Tue 3-4pm weeks 1-14")?.type == .course)
        #expect(p("Interview Tue 3-4pm biweekly")?.type == .course)
        #expect(p("Interview Tue 3-4pm #course")?.type == .course)
    }

    @Test func aLoneWeekdayPlusARangeOnAnAppointmentTitleIsAnEvent() {
        let e = p("Dentist Thu 2-3pm")?.asEvent
        #expect(e?.kind == .appointment)
        #expect(e?.day == d(9, 10))
        #expect(e?.startMinute == 840)
        #expect(e?.endMinute == 900)
        #expect(e?.title == "Dentist")
    }

    // MARK: Todos

    @Test func aWeekdayWithNoTimeAndNoEventKindIsATodo() {
        let t = p("Call mom Tue")?.asTodo
        #expect(t?.title == "Call mom")
        #expect(t?.day == d(9, 15))
        #expect(t?.week == nil)
        #expect(t?.priority == 3)
        #expect(p("Call mom Tue")?.type == .todo)
    }

    @Test func plainTextIsATodoDueToday() {
        let t = p("Finish lab report")?.asTodo
        #expect(t?.title == "Finish lab report")
        #expect(t?.day == d(9, 9))
        #expect(t?.projectName == nil)
    }

    @Test func bangPrioritiesAndProjectTags() {
        let t = p("Email advisor !1 #thesis")?.asTodo
        #expect(t?.priority == 1)
        #expect(t?.projectName == "Thesis")     // canonical name from the context
        #expect(t?.title == "Email advisor")
    }

    @Test func wordPrioritiesAndPStyleTokens() {
        #expect(p("!urgent Fix build")?.asTodo?.priority == 1)
        #expect(p("Refactor !high")?.asTodo?.priority == 2)
        #expect(p("Water plants !low")?.asTodo?.priority == 4)
        #expect(p("Submit form p2 tomorrow")?.asTodo?.priority == 2)
        #expect(p("Submit form p2 tomorrow")?.asTodo?.day == d(9, 10))
        #expect(p("Submit form p2 tomorrow")?.asTodo?.title == "Submit form")
    }

    @Test func thisWeekAndNextWeekBucketTheTodo() {
        let this = p("Draft outline this week")?.asTodo
        #expect(this?.week == d(9, 7))
        #expect(this?.day == nil)
        #expect(this?.title == "Draft outline")

        let next = p("Plan trip next week")?.asTodo
        #expect(next?.week == d(9, 14))
        #expect(next?.day == nil)
    }

    @Test func somedayClearsBothDayAndWeek() {
        for text in ["Read paper someday", "Read paper later", "Read paper backlog"] {
            let t = p(text)?.asTodo
            #expect(t?.day == nil)
            #expect(t?.week == nil)
            #expect(t?.title == "Read paper")
        }
    }

    @Test func unknownTagsKeepTheirRawText() {
        let t = p("Write notes #lab-report")?.asTodo
        #expect(t?.projectName == "lab-report")
        #expect(t?.title == "Write notes")
    }

    @Test func aKindNamedTagOnATodoIsStillAProjectTag() {
        let t = p("Prep slides #exam")?.asTodo
        #expect(t?.projectName == "exam")
        #expect(t?.title == "Prep slides")
    }

    @Test func emailAddressesAreNotLocations() {
        let t = p("Email bob@example.com Tue")?.asTodo
        #expect(t?.title == "Email bob@example.com")
        #expect(t?.day == d(9, 15))
    }

    @Test func numberRangesThatAreNotDatesStayInTheTodoTitle() {
        let t = p("Read pages 8-9")?.asTodo
        #expect(t?.title == "Read pages 8-9")
        #expect(t?.day == d(9, 9))
    }

    @Test func explicitDatesOnTodosPinTheDay() {
        let t = p("Submit transcript Sep 14")?.asTodo
        #expect(t?.day == d(9, 14))
        #expect(t?.title == "Submit transcript")
    }

    // MARK: Explicit prefixes

    @Test func prefixesForceTheType() {
        #expect(p("todo Interview Tue 3pm")?.type == .todo)
        #expect(p("task Interview Tue 3pm")?.type == .todo)
        #expect(p("event Lunch Tue")?.type == .event)
        #expect(p("class Yoga Mon 7am")?.type == .course)
    }

    @Test func coursePrefixWithASingleTimeGuessesAnHour() {
        let c = p("course Yoga Mon 7am")?.asCourse
        #expect(c?.weekdays == [.monday])
        #expect(c?.startMinute == 420)
        #expect(c?.endMinute == 480)
        #expect(c?.title == "Yoga")
    }

    @Test func eventPrefixWithNoDateIsAllDayToday() {
        let e = p("event Party")?.asEvent
        #expect(e?.day == d(9, 9))
        #expect(e?.startMinute == nil)
        #expect(e?.title == "Party")
    }

    // MARK: forcing

    @Test func forcingTodoAlwaysSucceeds() {
        let t = p("Interview Tue 3pm", forcing: .todo)?.asTodo
        #expect(t?.day == d(9, 15))
        #expect(t?.title == "Interview 3pm")
        #expect(p("today", forcing: .todo)?.type == .todo)
        #expect(p("clear courses weeks 8-9", forcing: .todo)?.type == .todo)
    }

    @Test func forcingCourseWithoutATimeRangeUsesDefaults() {
        let c = p("Study group", forcing: .course)?.asCourse
        #expect(c?.weekdays.isEmpty == true)
        #expect(c?.startMinute == 540)
        #expect(c?.endMinute == 600)
        #expect(c?.title == "Study group")
    }

    @Test func forcingEventWithoutADateIsAllDayToday() {
        let e = p("Buy milk", forcing: .event)?.asEvent
        #expect(e?.day == d(9, 9))
        #expect(e?.startMinute == nil)
        #expect(e?.title == "Buy milk")
    }

    @Test func forcingBeatsAnExplicitPrefix() {
        let c = p("todo CS201 MWF 10-11", forcing: .course)?.asCourse
        #expect(c?.weekdays == [.monday, .wednesday, .friday])
        #expect(c?.startMinute == 600 && c?.endMinute == 660)
        #expect(c?.title == "CS201")
    }

    @Test func forcingCourseWithoutATermStillFallsThrough() {
        #expect(p("CS201 MWF 10-11", forcing: .course, in: termless)?.asCourse == nil)
    }

    // MARK: Bare-hour conventions

    @Test func bareHoursFollowTheOneToSevenPmConvention() {
        #expect(p("Lab Fri 9-10 weeks 1-2")?.asCourse?.startMinute == 540)   // 9 → am
        #expect(p("Lab Fri 1-2 weeks 1-2")?.asCourse?.startMinute == 780)    // 1 → pm
        #expect(p("Lab Fri 12-1 weeks 1-2")?.asCourse?.startMinute == 720)   // 12 → noon
        #expect(p("Lab Fri 12-1 weeks 1-2")?.asCourse?.endMinute == 780)
        #expect(p("Talk today at 8")?.asEvent?.startMinute == 480)           // 8 → am
    }

    // MARK: NSDataDetector fallback

    @Test func dataDetectorHandlesPhrasingTheHandParserDoesNot() {
        let cmd = p("Dentist on the 14th of September at 2pm")
        let e = cmd?.asEvent
        #expect(e != nil)
        #expect(e?.kind == .appointment)
        #expect(e?.startMinute == 840)
        // The detector resolves the year relative to the real clock, so only the civil month/day is asserted.
        #expect(e?.day.month == 9)
        #expect(e?.day.day == 14)
        #expect(e?.title == "Dentist")
    }
}
