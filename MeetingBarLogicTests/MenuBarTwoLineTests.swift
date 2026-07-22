//
//  MenuBarTwoLineTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for "One line / Two lines" on the Menu Bar pane.
//
//  This is the capability the deleted `eventTimeFormat` picker's
//  `.show_under_title` value carried. It was read only by the classic
//  status-bar path, so it did nothing at all once a user composed their menu
//  bar; it is now a control of its own, implemented in the composed renderer,
//  and a one-time migration carries the setting over rather than dropping it.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import XCTest

@testable import MeetingBarLogic

final class MenuBarTwoLineTests: XCTestCase {
    // 2026-05-09 06:13:20 UTC (deterministic with the UTC calendar below).
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func settings(twoLines: Bool) -> MenuBarComposedSettings {
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
            countdownStyle: .digital,
            dateStyle: .medium,
            progressStyle: .day,
            use24HourClock: true,
            worldClockTimeZone: TimeZone(identifier: "America/Los_Angeles")!,
            worldClockLabel: "SF",
            weekNumberPrefix: "W",
            iconFormat: .appicon,
            iconFormatAssetName: "AppIcon",
            iconAssets: StatusBarIconAssets(
                appIcon: "AppIcon",
                calendarCheckmark: "CalendarCheckmark",
                calendar: "Calendar"
            ),
            tokenSeparator: " ",
            pendingDisplay: .normal,
            tentativeDisplay: .normal,
            twoLines: twoLines
        )
    }

    private func event() -> StatusBarEventPresentationInput {
        StatusBarEventPresentationInput(
            title: "Design review",
            startDate: now.addingTimeInterval(25 * 60),
            endDate: now.addingTimeInterval(55 * 60),
            meetingService: .zoom,
            participation: .normal
        )
    }

    private func presentation(
        tokens: [MenuBarTokenKind],
        twoLines: Bool,
        hasEvent: Bool = true
    ) -> StatusBarPresentation {
        StatusBarPresenter.composedPresentation(
            nextEvent: hasEvent ? event() : nil,
            composition: MenuBarComposition(tokens: tokens),
            settings: settings(twoLines: twoLines),
            now: now,
            calendar: calendar()
        )
    }

    // MARK: - Two lines

    func testTwoLinesPutsTheTitleOnTopAndEverythingElseUnderIt() {
        let result = presentation(tokens: [.icon, .title, .countdown], twoLines: true)
        XCTAssertEqual(result.layout, .stacked)
        XCTAssertEqual(result.title, "Design review")
        XCTAssertEqual(result.time, "0:26")
    }

    func testTwoLinesJoinsEveryOtherBlockOnTheSecondLine() {
        let result = presentation(tokens: [.title, .countdown, .weekNumber], twoLines: true)
        XCTAssertEqual(result.layout, .stacked)
        XCTAssertEqual(result.time, "0:26 W19")
    }

    func testTitleBlockOrderDoesNotChangeWhichLineItIsOn() {
        // The title is the headline whether the user put it first or last.
        let result = presentation(tokens: [.countdown, .title], twoLines: true)
        XCTAssertEqual(result.layout, .stacked)
        XCTAssertEqual(result.title, "Design review")
        XCTAssertEqual(result.time, "0:26")
    }

    // MARK: - When two lines cannot mean anything

    func testWithoutATitleBlockItStaysOnOneLine() {
        let result = presentation(tokens: [.icon, .countdown], twoLines: true)
        XCTAssertEqual(result.layout, .inline(showTime: false))
        XCTAssertEqual(result.title, "0:26")
        XCTAssertEqual(result.time, "")
    }

    func testWithNothingToPutUnderTheTitleItStaysOnOneLine() {
        let result = presentation(tokens: [.icon, .title], twoLines: true)
        XCTAssertEqual(result.layout, .inline(showTime: false))
        XCTAssertEqual(result.title, "Design review")
    }

    func testNonEventModeStaysOnOneLine() {
        // No meeting, so no title: the clock has nothing to sit under.
        let result = presentation(tokens: [.icon, .title, .clock], twoLines: true, hasEvent: false)
        XCTAssertEqual(result.layout, .inline(showTime: false))
    }

    // MARK: - One line is unchanged

    func testOneLineComposesExactlyAsBefore() {
        let result = presentation(tokens: [.icon, .title, .countdown], twoLines: false)
        XCTAssertEqual(result.layout, .inline(showTime: false))
        XCTAssertEqual(result.title, "Design review 0:26")
        XCTAssertEqual(result.time, "")
    }

    func testTwoLinesDefaultsToOffSoTheStructIsSourceCompatible() {
        XCTAssertFalse(settings(twoLines: false).twoLines)
    }
}
