//
//  MenuBarCountdownLeadTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for how early the Countdown block starts counting.
//

import XCTest

@testable import MeetingBarLogic

final class MenuBarCountdownLeadTests: XCTestCase {
    // 2026-05-09 06:13:20 UTC.
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func shows(startsIn: TimeInterval, lasts: TimeInterval = 1800, lead: Int) -> Bool {
        MenuBarCompositionPolicy.showsCountdown(
            start: now.addingTimeInterval(startsIn),
            end: now.addingTimeInterval(startsIn + lasts),
            now: now,
            leadMinutes: lead
        )
    }

    // MARK: - The rule

    func testNoLimitByDefault() {
        XCTAssertTrue(
            shows(startsIn: 8 * 3600, lead: 0),
            "0 must mean no limit — it is the shipped default, and anything else would "
                + "silently change every existing menu bar"
        )
    }

    func testHiddenBeyondTheLead() {
        // The case this setting was added for: a 3h40m-away evening block.
        XCTAssertFalse(shows(startsIn: 3 * 3600 + 40 * 60, lead: 60))
    }

    func testShownInsideTheLead() {
        XCTAssertTrue(shows(startsIn: 45 * 60, lead: 60))
    }

    func testShownExactlyOnTheBoundary() {
        XCTAssertTrue(shows(startsIn: 60 * 60, lead: 60))
    }

    func testHiddenJustOutsideTheBoundary() {
        XCTAssertFalse(shows(startsIn: 60 * 60 + 1, lead: 60))
    }

    func testARunningMeetingAlwaysCountsDown() {
        XCTAssertTrue(
            shows(startsIn: -300, lasts: 1800, lead: 1),
            "a meeting in progress counts down to its END, whatever the lead is"
        )
    }

    func testAFinishedMeetingDoesNot() {
        XCTAssertFalse(shows(startsIn: -3600, lasts: 1800, lead: 60))
    }

    func testANegativeLeadDegradesToNoLimit() {
        XCTAssertTrue(
            shows(startsIn: 8 * 3600, lead: -30),
            "a corrupt preference should show more, never blank the block"
        )
    }

    // MARK: - The redraw clock

    func testAppearanceDateIsTheLeadBoundary() {
        let start = now.addingTimeInterval(4 * 3600)
        XCTAssertEqual(
            MenuBarCompositionPolicy.countdownAppearanceDate(eventStart: start, leadMinutes: 60),
            start.addingTimeInterval(-3600)
        )
    }

    func testNoAppearanceDateWithoutALimit() {
        XCTAssertNil(
            MenuBarCompositionPolicy.countdownAppearanceDate(
                eventStart: now.addingTimeInterval(3600),
                leadMinutes: 0
            ),
            "an always-visible countdown has no transition to wake the timer for"
        )
    }

    // MARK: - Through the composed presenter

    private func settings(countdownLeadMinutes: Int) -> MenuBarComposedSettings {
        MenuBarComposedSettings(
            presentation: StatusBarPresentationSettings(
                hasSelectedCalendars: true,
                showEventMaxTimeUntilEventEnabled: false,
                showEventMaxTimeUntilEventThreshold: 60
            ),
            title: StatusBarTitleSettings(
                titleFormat: .show,
                titleLength: 55,
                labels: StatusBarTitleLabels(
                    genericMeetingTitle: "Meeting",
                    noTitle: "No title",
                    activeEventTimeFormat: "now (%@ left)",
                    upcomingEventTimeFormat: "in %@"
                )
            ),
            countdownStyle: .full,
            countdownLeadMinutes: countdownLeadMinutes,
            dateStyle: .medium,
            progressStyle: .day,
            use24HourClock: true,
            worldClockTimeZone: TimeZone(identifier: "UTC")!,
            worldClockLabel: "",
            weekNumberPrefix: "W",
            iconFormat: .appicon,
            iconFormatAssetName: "AppIcon",
            iconAssets: StatusBarIconAssets(
                appIcon: "AppIcon",
                calendarCheckmark: "iconCalendarCheckmark",
                calendar: "iconCalendar"
            ),
            tokenSeparator: " ",
            pendingDisplay: .normal,
            tentativeDisplay: .normal
        )
    }

    private func present(startsIn: TimeInterval, lead: Int, twoLines: Bool = false) -> StatusBarPresentation {
        var settings = settings(countdownLeadMinutes: lead)
        settings.twoLines = twoLines
        return StatusBarPresenter.composedPresentation(
            nextEvent: StatusBarEventPresentationInput(
                title: "Journalling",
                startDate: now.addingTimeInterval(startsIn),
                endDate: now.addingTimeInterval(startsIn + 1800),
                meetingService: nil,
                participation: .normal
            ),
            composition: MenuBarComposition(tokens: [.icon, .title, .countdown]),
            settings: settings,
            now: now,
            calendar: calendar()
        )
    }

    func testTheTitleSurvivesWhenTheCountdownIsSuppressed() {
        let presentation = present(startsIn: 3 * 3600 + 40 * 60, lead: 60)
        XCTAssertEqual(
            presentation.title,
            "Journalling",
            "hiding the countdown must not hide the meeting — that is what the "
                + "quiet threshold is for, and it is a different question"
        )
    }

    func testTheCountdownReturnsInsideTheWindow() {
        let presentation = present(startsIn: 30 * 60, lead: 60)
        XCTAssertTrue(presentation.title.hasPrefix("Journalling"))
        // Matched as a shape, not a number: the presenter counts from a minute
        // BEFORE now so a countdown rounds up rather than down (30 minutes away
        // reads "31m"), and pinning the digits here would be asserting that
        // unrelated behaviour rather than this setting's.
        XCTAssertNotNil(
            presentation.title.range(of: #"\d+m$"#, options: .regularExpression),
            "expected a countdown on the end of \(presentation.title)"
        )
    }

    /// A suppressed countdown must not leave a stack with an empty second row.
    func testTwoLineLayoutCollapsesWhenOnlyTheCountdownWasUnderneath() {
        let presentation = present(startsIn: 3 * 3600 + 40 * 60, lead: 60, twoLines: true)
        XCTAssertEqual(presentation.layout, .inline(showTime: false))
        XCTAssertEqual(presentation.title, "Journalling")
        XCTAssertEqual(presentation.time, "")
    }

    func testTwoLineLayoutStandsWhenTheCountdownIsShowing() {
        let presentation = present(startsIn: 30 * 60, lead: 60, twoLines: true)
        XCTAssertEqual(presentation.layout, .stacked)
        XCTAssertEqual(presentation.title, "Journalling")
        XCTAssertFalse(presentation.time.isEmpty)
    }
}
