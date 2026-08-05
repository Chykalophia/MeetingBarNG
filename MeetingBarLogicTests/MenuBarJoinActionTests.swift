//
//  MenuBarJoinActionTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for the menu bar's Join chip (MeetingBarNG): when it shows,
//  and where it lands.
//

import XCTest

@testable import MeetingBarLogic

final class MenuBarJoinActionTests: XCTestCase {
    // 2026-05-09 06:13:20 UTC.
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func settings(
        isEnabled: Bool = true,
        leadMinutes: Int = 2,
        label: String = "Join"
    ) -> MenuBarJoinActionSettings {
        MenuBarJoinActionSettings(isEnabled: isEnabled, leadMinutes: leadMinutes, label: label)
    }

    private func event(
        startOffset: TimeInterval,
        endOffset: TimeInterval,
        hasMeetingLink: Bool = true
    ) -> StatusBarEventPresentationInput {
        StatusBarEventPresentationInput(
            title: "Standup",
            startDate: now.addingTimeInterval(startOffset),
            endDate: now.addingTimeInterval(endOffset),
            meetingService: nil,
            participation: .normal,
            hasMeetingLink: hasMeetingLink
        )
    }

    // MARK: - When the chip shows

    func testShowsInsideTheLeadWindow() {
        // Starts in 90s, lead is 2 minutes.
        let label = MenuBarJoinActionPolicy.label(
            event: event(startOffset: 90, endOffset: 1800),
            settings: settings(),
            now: now
        )
        XCTAssertEqual(label, "Join")
    }

    func testHiddenBeforeTheLeadWindow() {
        // Starts in 3 minutes, lead is 2.
        let label = MenuBarJoinActionPolicy.label(
            event: event(startOffset: 180, endOffset: 1800),
            settings: settings(),
            now: now
        )
        XCTAssertEqual(label, "")
    }

    func testAppearsExactlyOnTheLeadBoundary() {
        let label = MenuBarJoinActionPolicy.label(
            event: event(startOffset: 120, endOffset: 1800),
            settings: settings(leadMinutes: 2),
            now: now
        )
        XCTAssertEqual(label, "Join", "the boundary itself is inside the window")
    }

    func testStaysForTheWholeMeeting() {
        // Started 20 minutes ago, ends in 10.
        let label = MenuBarJoinActionPolicy.label(
            event: event(startOffset: -1200, endOffset: 600),
            settings: settings(),
            now: now
        )
        XCTAssertEqual(label, "Join", "joining late is legitimate")
    }

    func testClearsOnceTheMeetingHasEnded() {
        let label = MenuBarJoinActionPolicy.label(
            event: event(startOffset: -3600, endOffset: -60),
            settings: settings(),
            now: now
        )
        XCTAssertEqual(label, "")
    }

    func testZeroLeadMeansOnlyWhileRunning() {
        let settings = settings(leadMinutes: 0)
        XCTAssertEqual(
            MenuBarJoinActionPolicy.label(
                event: event(startOffset: 30, endOffset: 1800), settings: settings, now: now
            ),
            "",
            "half a minute out is still not running"
        )
        XCTAssertEqual(
            MenuBarJoinActionPolicy.label(
                event: event(startOffset: -30, endOffset: 1800), settings: settings, now: now
            ),
            "Join"
        )
    }

    func testNegativeLeadIsClampedRatherThanInverted() {
        let label = MenuBarJoinActionPolicy.label(
            event: event(startOffset: 60, endOffset: 1800),
            settings: settings(leadMinutes: -30),
            now: now
        )
        XCTAssertEqual(label, "", "a corrupt preference degrades to 'only while running'")
    }

    func testHiddenWhenDisabled() {
        let label = MenuBarJoinActionPolicy.label(
            event: event(startOffset: 30, endOffset: 1800),
            settings: settings(isEnabled: false),
            now: now
        )
        XCTAssertEqual(label, "")
    }

    func testHiddenWithoutSomewhereToJoin() {
        let label = MenuBarJoinActionPolicy.label(
            event: event(startOffset: 30, endOffset: 1800, hasMeetingLink: false),
            settings: settings(),
            now: now
        )
        XCTAssertEqual(label, "", "a chip that opens nothing is worse than no chip")
    }

    func testBlankLabelYieldsNoChip() {
        let label = MenuBarJoinActionPolicy.label(
            event: event(startOffset: 30, endOffset: 1800),
            settings: settings(label: "   "),
            now: now
        )
        XCTAssertEqual(label, "")
    }

    func testLabelIsTrimmed() {
        let label = MenuBarJoinActionPolicy.label(
            event: event(startOffset: 30, endOffset: 1800),
            settings: settings(label: "  Join  "),
            now: now
        )
        XCTAssertEqual(label, "Join", "stray whitespace would widen the chip's measured run")
    }

    // MARK: - The redraw clock

    func testAppearanceDateIsTheLeadBoundary() {
        let start = now.addingTimeInterval(600)
        XCTAssertEqual(
            MenuBarJoinActionPolicy.appearanceDate(eventStart: start, settings: settings(leadMinutes: 2)),
            start.addingTimeInterval(-120)
        )
    }

    func testAppearanceDateIsNilWhenDisabled() {
        XCTAssertNil(
            MenuBarJoinActionPolicy.appearanceDate(
                eventStart: now.addingTimeInterval(600),
                settings: settings(isEnabled: false)
            ),
            "a chip nobody asked for should not wake the timer"
        )
    }

    func testAppearanceDateClampsANegativeLead() {
        let start = now.addingTimeInterval(600)
        XCTAssertEqual(
            MenuBarJoinActionPolicy.appearanceDate(eventStart: start, settings: settings(leadMinutes: -5)),
            start
        )
    }

    // MARK: - Through the composed presenter

    private func composedSettings(
        joinAction: MenuBarJoinActionSettings,
        twoLines: Bool = false
    ) -> MenuBarComposedSettings {
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
            tentativeDisplay: .normal,
            twoLines: twoLines,
            joinAction: joinAction
        )
    }

    private func present(
        tokens: [MenuBarTokenKind],
        event: StatusBarEventPresentationInput?,
        settings: MenuBarComposedSettings
    ) -> StatusBarPresentation {
        StatusBarPresenter.composedPresentation(
            nextEvent: event,
            composition: MenuBarComposition(tokens: tokens),
            settings: settings,
            now: now,
            calendar: calendar()
        )
    }

    func testChipIsTheTrailingRunOfTheOneLine() {
        let presentation = present(
            tokens: [.icon, .title, .countdown],
            event: event(startOffset: 60, endOffset: 1800),
            settings: composedSettings(joinAction: settings())
        )
        XCTAssertEqual(presentation.actionLabel, "Join")
        XCTAssertTrue(
            presentation.title.hasSuffix(" Join"),
            "the renderer measures the chip as the trailing run: \(presentation.title)"
        )
        XCTAssertTrue(presentation.title.hasPrefix("Standup"))
    }

    func testChipRidesTheDetailLineOfTheStack() {
        let presentation = present(
            tokens: [.icon, .title, .countdown],
            event: event(startOffset: 60, endOffset: 1800),
            settings: composedSettings(joinAction: settings(), twoLines: true)
        )
        XCTAssertEqual(presentation.layout, .stacked)
        XCTAssertEqual(presentation.title, "Standup", "the headline is still just the title")
        XCTAssertTrue(
            presentation.time.hasSuffix("Join"),
            "the chip is last on the drawn line: \(presentation.time)"
        )
    }

    func testChipAloneWhenNoBlockIsShowing() {
        let presentation = present(
            tokens: [],
            event: event(startOffset: 60, endOffset: 1800),
            settings: composedSettings(joinAction: settings())
        )
        XCTAssertEqual(presentation.title, "Join")
        XCTAssertEqual(presentation.layout, .inline(showTime: false))
    }

    func testStackFallsBackToOneLineWhenTheChipIsAllThereIsBesideTheTitle() {
        let presentation = present(
            tokens: [.title],
            event: event(startOffset: 60, endOffset: 1800),
            settings: composedSettings(joinAction: settings(), twoLines: true)
        )
        XCTAssertEqual(presentation.layout, .stacked)
        XCTAssertEqual(presentation.title, "Standup")
        XCTAssertEqual(presentation.time, "Join")
    }

    func testTitleIsUntouchedWhenTheChipIsOff() {
        let presentation = present(
            tokens: [.title],
            event: event(startOffset: 60, endOffset: 1800),
            settings: composedSettings(joinAction: settings(isEnabled: false))
        )
        XCTAssertEqual(presentation.actionLabel, "")
        XCTAssertEqual(presentation.title, "Standup")
    }

    func testNonEventModesNeverGetAChip() {
        let presentation = present(
            tokens: [.icon, .clock],
            event: nil,
            settings: composedSettings(joinAction: settings())
        )
        XCTAssertEqual(presentation.mode, .noUpcoming)
        XCTAssertEqual(presentation.actionLabel, "")
    }

    // MARK: - Geometry

    /// A 100×22 item: 16pt icon on the left, 70pt of title, 4pt inset each side.
    private func metrics(
        buttonWidth: CGFloat = 100,
        imageWidth: CGFloat = 16,
        imageIsTrailing: Bool = false,
        titleWidth: CGFloat = 70,
        lineWidth: CGFloat? = nil,
        labelWidth: CGFloat = 26,
        isStacked: Bool = false
    ) -> MenuBarActionChipMetrics {
        MenuBarActionChipMetrics(
            buttonBounds: CGRect(x: 0, y: 0, width: buttonWidth, height: 22),
            imageWidth: imageWidth,
            imageIsTrailing: imageIsTrailing,
            titleWidth: titleWidth,
            lineWidth: lineWidth ?? titleWidth,
            labelWidth: labelWidth,
            isStacked: isStacked
        )
    }

    func testChipEndsAtTheTitlesTrailingEdge() {
        let chip = MenuBarActionChipGeometry.rect(metrics())
        let padding = MenuBarActionChipGeometry.horizontalPadding
        // inset = (100 - (70 + 16 + 2)) / 2 = 6; title box is 24...94.
        XCTAssertEqual(chip?.maxX ?? 0, 94 + padding, accuracy: 0.01)
        XCTAssertEqual(chip?.width ?? 0, 26 + padding * 2, accuracy: 0.01)
    }

    func testATrailingIconPushesTheChipLeft() {
        let withLeadingIcon = MenuBarActionChipGeometry.rect(metrics())
        let withTrailingIcon = MenuBarActionChipGeometry.rect(metrics(imageIsTrailing: true))
        XCTAssertNotNil(withTrailingIcon)
        XCTAssertEqual(
            (withLeadingIcon?.maxX ?? 0) - (withTrailingIcon?.maxX ?? 0),
            16 + MenuBarActionChipGeometry.imageTitleSpacing,
            accuracy: 0.01,
            "the chip clears the icon the user placed last"
        )
    }

    func testChipFollowsItsOwnLineOnTheStack() {
        // The detail line is 30pt under a 70pt title, and centred — so the chip
        // has to stop 20pt short of where the wide line ends.
        let chip = MenuBarActionChipGeometry.rect(
            metrics(lineWidth: 30, isStacked: true)
        )
        let wide = MenuBarActionChipGeometry.rect(metrics())
        XCTAssertEqual(
            (wide?.maxX ?? 0) - (chip?.maxX ?? 0),
            20,
            accuracy: 0.01,
            "anchoring to the item's edge would leave the capsule floating past the text"
        )
    }

    func testStackedChipSitsOnTheLowerLine() {
        let chip = MenuBarActionChipGeometry.rect(metrics(lineWidth: 30, isStacked: true))
        XCTAssertNotNil(chip)
        XCTAssertLessThan(chip?.midY ?? .infinity, 11, "y-up: the detail line is at the bottom")
    }

    func testNoChipWithoutALabel() {
        XCTAssertNil(MenuBarActionChipGeometry.rect(metrics(labelWidth: 0)))
    }

    func testNoChipWhenItWouldOverrunTheItem() {
        XCTAssertNil(
            MenuBarActionChipGeometry.rect(metrics(buttonWidth: 20, titleWidth: 0, labelWidth: 40))
        )
    }

    func testEdgeInsetFallsBackOnAnImplausibleMeasurement() {
        // A content width wider than the button (a mis-measure) would otherwise
        // produce a negative inset and push the chip off the right edge.
        XCTAssertEqual(
            MenuBarActionChipGeometry.edgeInset(buttonWidth: 100, contentWidth: 140),
            MenuBarActionChipGeometry.fallbackEdgeInset
        )
        XCTAssertEqual(
            MenuBarActionChipGeometry.edgeInset(buttonWidth: 100, contentWidth: 10),
            MenuBarActionChipGeometry.fallbackEdgeInset,
            "45pt of padding is not an inset, it is a bad measurement"
        )
        XCTAssertEqual(MenuBarActionChipGeometry.edgeInset(buttonWidth: 100, contentWidth: 92), 4)
    }

    func testHitRectMatchesTheCapsuleHorizontallyAndFillsTheItemVertically() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 22)
        let chip = CGRect(x: 60, y: 2, width: 30, height: 10)
        let hit = MenuBarActionChipGeometry.hitRect(chip: chip, buttonBounds: bounds)
        XCTAssertEqual(hit.minX, chip.minX)
        XCTAssertEqual(hit.width, chip.width)
        XCTAssertEqual(hit.minY, bounds.minY)
        XCTAssertEqual(hit.height, bounds.height)
    }
}
