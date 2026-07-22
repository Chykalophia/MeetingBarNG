//
//  StatusBarCompositionPolicyTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for the composable menu-bar policy (MeetingBarNG).
//

import XCTest

@testable import MeetingBarLogic

final class StatusBarCompositionPolicyTests: XCTestCase {
    // 2026-05-09 06:13:20 UTC (deterministic with the UTC calendar below).
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func assertMatches(
        _ value: String,
        _ pattern: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNotNil(
            value.range(of: pattern, options: .regularExpression),
            "\"\(value)\" did not match /\(pattern)/",
            file: file, line: line
        )
    }

    // MARK: - Settings / event builders

    private func settings(
        tokenSeparator: String = " ",
        countdownStyle: CountdownStyle = .full,
        dateStyle: MenuBarDateStyle = .medium,
        progressStyle: MenuBarProgressStyle = .day,
        use24HourClock: Bool = true,
        worldClockTimeZone: TimeZone = TimeZone(identifier: "America/Los_Angeles")!,
        worldClockLabel: String = "SF",
        weekNumberPrefix: String = "W",
        iconFormat: StatusBarIconFormat = .appicon,
        titleFormat: StatusBarEventTitleFormat = .show,
        titleLength: Int = 55,
        maxTimeUntilEnabled: Bool = false,
        maxTimeUntilThreshold: Int = 60,
        hasSelectedCalendars: Bool = true,
        pendingDisplay: StatusBarParticipationDisplay = .normal,
        tentativeDisplay: StatusBarParticipationDisplay = .normal
    ) -> MenuBarComposedSettings {
        MenuBarComposedSettings(
            presentation: StatusBarPresentationSettings(
                hasSelectedCalendars: hasSelectedCalendars,
                showEventMaxTimeUntilEventEnabled: maxTimeUntilEnabled,
                showEventMaxTimeUntilEventThreshold: maxTimeUntilThreshold
            ),
            title: StatusBarTitleSettings(
                titleFormat: titleFormat,
                titleLength: titleLength,
                labels: StatusBarTitleLabels(
                    genericMeetingTitle: "Meeting",
                    noTitle: "No title",
                    activeEventTimeFormat: "now (%@ left)",
                    upcomingEventTimeFormat: "in %@"
                )
            ),
            countdownStyle: countdownStyle,
            dateStyle: dateStyle,
            progressStyle: progressStyle,
            use24HourClock: use24HourClock,
            worldClockTimeZone: worldClockTimeZone,
            worldClockLabel: worldClockLabel,
            weekNumberPrefix: weekNumberPrefix,
            iconFormat: iconFormat,
            iconFormatAssetName: "AppIcon",
            iconAssets: StatusBarIconAssets(
                appIcon: "AppIcon",
                calendarCheckmark: "iconCalendarCheckmark",
                calendar: "iconCalendar"
            ),
            tokenSeparator: tokenSeparator,
            pendingDisplay: pendingDisplay,
            tentativeDisplay: tentativeDisplay
        )
    }

    private func event(
        title: String? = "Standup",
        startOffset: TimeInterval = 600,
        endOffset: TimeInterval = 2400,
        participation: StatusBarEventParticipation = .normal
    ) -> StatusBarEventPresentationInput {
        StatusBarEventPresentationInput(
            title: title,
            startDate: now.addingTimeInterval(startOffset),
            endDate: now.addingTimeInterval(endOffset),
            meetingService: nil,
            participation: participation
        )
    }

    private func present(
        tokens: [MenuBarTokenKind],
        event: StatusBarEventPresentationInput?,
        settings: MenuBarComposedSettings? = nil
    ) -> StatusBarPresentation {
        StatusBarPresenter.composedPresentation(
            nextEvent: event,
            composition: MenuBarComposition(tokens: tokens),
            settings: settings ?? self.settings(),
            now: now,
            calendar: calendar()
        )
    }

    // MARK: - countdownText

    func testCountdownFullShowsAllUnits() {
        let result = MenuBarCompositionPolicy.countdownText(
            from: now, to: now.addingTimeInterval(9000), style: .full, calendar: calendar()
        )
        XCTAssertTrue(result.contains("2"), result)
        XCTAssertTrue(result.contains("30"), result)
    }

    func testCountdownCompactShowsOnlyLargestUnit() {
        // 2h30m compacts to a single (rounded) unit — no minutes component,
        // and therefore no inter-unit space.
        let result = MenuBarCompositionPolicy.countdownText(
            from: now, to: now.addingTimeInterval(9000), style: .compact, calendar: calendar()
        )
        XCTAssertFalse(result.isEmpty)
        XCTAssertFalse(result.contains(" "), result)
        XCTAssertFalse(result.contains("30"), result)
    }

    func testCountdownDigitalIsPositional() {
        let result = MenuBarCompositionPolicy.countdownText(
            from: now, to: now.addingTimeInterval(9000), style: .digital, calendar: calendar()
        )
        XCTAssertEqual(result, "2:30")
    }

    func testCountdownNonPositiveIntervalIsEmpty() {
        XCTAssertEqual(
            MenuBarCompositionPolicy.countdownText(
                from: now, to: now, style: .full, calendar: calendar()
            ),
            ""
        )
        XCTAssertEqual(
            MenuBarCompositionPolicy.countdownText(
                from: now, to: now.addingTimeInterval(-120), style: .digital, calendar: calendar()
            ),
            ""
        )
    }

    // MARK: - dateText / clockText

    func testDateWeekdayIsThreeLetters() {
        assertMatches(
            MenuBarCompositionPolicy.dateText(now: now, style: .weekday, calendar: calendar()),
            "^[A-Za-z]{3}$"
        )
    }

    func testDateMediumHasWeekdayMonthDay() {
        assertMatches(
            MenuBarCompositionPolicy.dateText(now: now, style: .medium, calendar: calendar()),
            "^[A-Za-z]{3}, [A-Za-z]{3} [0-9]{1,2}$"
        )
    }

    func testDateShortIsNumeric() {
        assertMatches(
            MenuBarCompositionPolicy.dateText(now: now, style: .short, calendar: calendar()),
            "^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}$"
        )
    }

    func testClock24HourHasNoMeridiem() {
        let result = MenuBarCompositionPolicy.clockText(now: now, use24Hour: true, calendar: calendar())
        assertMatches(result, "^[0-9]{1,2}:[0-9]{2}$")
        XCTAssertFalse(result.contains("AM"))
        XCTAssertFalse(result.contains("PM"))
    }

    func testClock12HourHasMeridiem() {
        let result = MenuBarCompositionPolicy.clockText(now: now, use24Hour: false, calendar: calendar())
        XCTAssertTrue(result.contains("AM") || result.contains("PM"), result)
        XCTAssertTrue(result.contains(":"), result)
    }

    // MARK: - composedPresentation: ordering

    func testTokenOrderIsPreserved() {
        let forward = present(tokens: [.title, .countdown], event: event())
        XCTAssertTrue(forward.title.hasPrefix("Standup"), forward.title)

        let reversed = present(tokens: [.countdown, .title], event: event())
        XCTAssertTrue(reversed.title.hasSuffix("Standup"), reversed.title)
    }

    func testSeparatorJoinsTextTokens() {
        let result = present(
            tokens: [.title, .clock],
            event: event(),
            settings: settings(tokenSeparator: " • ")
        )
        XCTAssertTrue(result.title.contains(" • "), result.title)
        XCTAssertTrue(result.title.hasPrefix("Standup • "), result.title)
    }

    // MARK: - composedPresentation: icon

    func testIconTokenSetsIcon() {
        let result = present(tokens: [.icon, .title], event: event())
        XCTAssertEqual(result.icon, .asset("AppIcon"))
    }

    func testMissingIconTokenLeavesNoIcon() {
        let result = present(tokens: [.title], event: event())
        XCTAssertEqual(result.icon, .none)
    }

    // MARK: - composedPresentation: non-event modes

    func testNoUpcomingRendersIconOnly() {
        let result = present(tokens: [.title, .countdown], event: nil)
        XCTAssertEqual(result.mode, .noUpcoming)
        XCTAssertEqual(result.title, "")
        XCTAssertEqual(result.layout, .none)
        XCTAssertEqual(result.icon, .asset("AppIcon"))
        XCTAssertTrue(result.removeDeliveredNotifications)
    }

    func testIdleRendersAppIcon() {
        let result = present(
            tokens: [.title],
            event: nil,
            settings: settings(hasSelectedCalendars: false)
        )
        XCTAssertEqual(result.mode, .idle)
        XCTAssertEqual(result.title, "")
        XCTAssertEqual(result.layout, .none)
        XCTAssertEqual(result.icon, .asset("AppIcon"))
    }

    func testAfterThresholdRendersNoText() {
        // Event starts 10 min out; threshold is 5 min and the toggle is on.
        let result = present(
            tokens: [.icon, .title, .countdown],
            event: event(startOffset: 600, endOffset: 2400),
            settings: settings(maxTimeUntilEnabled: true, maxTimeUntilThreshold: 5)
        )
        XCTAssertEqual(result.mode, .afterThreshold)
        XCTAssertEqual(result.title, "")
        XCTAssertEqual(result.layout, .none)
        XCTAssertEqual(result.icon, .asset("AppIcon"))
    }

    // MARK: - composedPresentation: title format / empty

    func testTitleFormatNoneOmitsTitleSegment() {
        let result = present(
            tokens: [.title, .clock],
            event: event(),
            settings: settings(titleFormat: .none)
        )
        // No leading separator, no title text — clock only.
        XCTAssertFalse(result.title.hasPrefix(" "), result.title)
        XCTAssertFalse(result.title.contains("Standup"), result.title)
        XCTAssertFalse(result.title.isEmpty, result.title)
    }

    func testAllEmptySegmentsRenderNoText() {
        // Only a title token, but the title format produces nothing.
        let result = present(
            tokens: [.title],
            event: event(),
            settings: settings(titleFormat: .none)
        )
        XCTAssertEqual(result.title, "")
        XCTAssertEqual(result.layout, .none)
        XCTAssertEqual(result.icon, .none)
    }

    func testGenericTitleFormatUsesGenericLabel() {
        let result = present(
            tokens: [.title],
            event: event(),
            settings: settings(titleFormat: .generic)
        )
        XCTAssertEqual(result.title, "Meeting")
    }

    // MARK: - composedPresentation: countdown target (active vs upcoming)

    func testUpcomingEventCountsDownToStart() {
        let result = present(
            tokens: [.countdown],
            event: event(startOffset: 600, endOffset: 2400),
            settings: settings(countdownStyle: .digital)
        )
        // start is 10 min out; with the -60 s rounding offset this reads 11 min.
        XCTAssertTrue(result.title.contains("11"), result.title)
    }

    func testActiveEventCountsDownToEnd() {
        let result = present(
            tokens: [.countdown],
            event: event(startOffset: -300, endOffset: 900),
            settings: settings(countdownStyle: .digital)
        )
        // Active event: counts to end (15 min out; +60 s offset → 16).
        XCTAssertTrue(result.title.contains("16"), result.title)
    }

    // MARK: - composedPresentation: participation styling

    func testPendingUnderlinedStyleApplies() {
        let result = present(
            tokens: [.title],
            event: event(participation: .pending),
            settings: settings(pendingDisplay: .underlined)
        )
        XCTAssertEqual(result.titleStyle, .underlined)
    }

    func testPendingInactiveIsNormalInlineLayout() {
        // Inactive styling only applies to the stacked layout; composed titles
        // are always inline, so pending-inactive renders as normal.
        let result = present(
            tokens: [.title],
            event: event(participation: .pending),
            settings: settings(pendingDisplay: .inactive)
        )
        XCTAssertEqual(result.titleStyle, .normal)
    }

    func testTooltipIsFullEventTitle() {
        let result = present(tokens: [.title], event: event(title: "Weekly sync"))
        XCTAssertEqual(result.tooltip, "Weekly sync")
    }

    // MARK: - composedPresentation: icon position

    func testIconLeadingWhenFirstToken() {
        let result = present(tokens: [.icon, .title], event: event())
        XCTAssertEqual(result.iconPosition, .leading)
    }

    func testIconTrailingWhenAfterText() {
        let result = present(tokens: [.title, .icon], event: event())
        XCTAssertEqual(result.iconPosition, .trailing)
    }

    func testIconLeadingWhenPrecedingTextIsEmpty() {
        // Title format .none emits no text, so an icon after it is still leading.
        let result = present(
            tokens: [.title, .icon],
            event: event(),
            settings: settings(titleFormat: .none)
        )
        XCTAssertEqual(result.iconPosition, .leading)
    }

    // MARK: - composedPresentation: non-event clock/date

    func testNonEventRendersClockToken() {
        let result = present(tokens: [.icon, .clock], event: nil)
        XCTAssertEqual(result.mode, .noUpcoming)
        XCTAssertFalse(result.title.isEmpty, result.title)
        assertMatches(result.title, "[0-9]{1,2}:[0-9]{2}")
        XCTAssertEqual(result.layout, .inline(showTime: false))
        XCTAssertEqual(result.icon, .asset("AppIcon"))
        XCTAssertEqual(result.iconPosition, .leading)
    }

    func testNonEventDropsEventDependentTokens() {
        // title + countdown need an event; with none they vanish, leaving date.
        let result = present(tokens: [.date, .title, .countdown], event: nil)
        XCTAssertEqual(result.mode, .noUpcoming)
        XCTAssertFalse(result.title.contains("Standup"), result.title)
        assertMatches(result.title, "^[A-Za-z]{3}, [A-Za-z]{3} [0-9]{1,2}$")
    }

    func testNonEventIconTrailingAfterDate() {
        let result = present(tokens: [.date, .icon], event: nil)
        XCTAssertEqual(result.iconPosition, .trailing)
    }

    // MARK: - countdownText: multi-day digital

    func testCountdownDigitalPrefixesDaysBeyondOneDay() {
        // 26 h → "1d 2:00"
        let result = MenuBarCompositionPolicy.countdownText(
            from: now, to: now.addingTimeInterval(26 * 3600), style: .digital, calendar: calendar()
        )
        XCTAssertEqual(result, "1d 2:00")
    }

    // MARK: - progressBarText

    func testProgressBarTextEmptyAndFull() {
        XCTAssertEqual(MenuBarCompositionPolicy.progressBarText(fraction: 0, width: 8), "░░░░░░░░")
        XCTAssertEqual(MenuBarCompositionPolicy.progressBarText(fraction: 1, width: 8), "████████")
    }

    func testProgressBarTextHalfIsHalfFilled() {
        XCTAssertEqual(MenuBarCompositionPolicy.progressBarText(fraction: 0.5, width: 8), "████░░░░")
    }

    func testProgressBarTextRendersPartialCell() {
        // 1/16 of an 8-cell bar = half of the first cell → a single eighth-block.
        let result = MenuBarCompositionPolicy.progressBarText(fraction: 1.0 / 16.0, width: 8)
        XCTAssertEqual(result, "▌░░░░░░░")
    }

    func testProgressBarTextClampsOutOfRange() {
        XCTAssertEqual(MenuBarCompositionPolicy.progressBarText(fraction: 1.5, width: 8), "████████")
        XCTAssertEqual(MenuBarCompositionPolicy.progressBarText(fraction: -0.5, width: 8), "░░░░░░░░")
    }

    func testProgressBarWidthIsAlwaysRespected() {
        for fraction in stride(from: 0.0, through: 1.0, by: 0.017) {
            XCTAssertEqual(
                MenuBarCompositionPolicy.progressBarText(fraction: fraction, width: 8).count, 8,
                "fraction \(fraction)"
            )
        }
    }

    func testProgressBarZeroWidthIsEmpty() {
        XCTAssertEqual(MenuBarCompositionPolicy.progressBarText(fraction: 0.5, width: 0), "")
    }

    // MARK: - dayFraction / yearFraction / progressFraction

    func testDayFractionAtMidnightIsZero() {
        let midnight = calendar().startOfDay(for: now)
        XCTAssertEqual(MenuBarCompositionPolicy.dayFraction(now: midnight, calendar: calendar()), 0, accuracy: 1e-9)
    }

    func testDayFractionMatchesElapsedSeconds() {
        // Reference instant is 06:13:20 UTC → 22 400 s of an 86 400 s day.
        let fraction = MenuBarCompositionPolicy.dayFraction(now: now, calendar: calendar())
        XCTAssertEqual(fraction, 22_400.0 / 86_400.0, accuracy: 1e-6)
    }

    func testDayFractionNearEndOfDayApproachesOne() {
        let midnight = calendar().startOfDay(for: now)
        let endOfDay = midnight.addingTimeInterval(86_400 - 1)
        let fraction = MenuBarCompositionPolicy.dayFraction(now: endOfDay, calendar: calendar())
        XCTAssertGreaterThan(fraction, 0.999)
        XCTAssertLessThanOrEqual(fraction, 1.0)
    }

    func testYearFractionAtStartOfYearIsZero() {
        let startOfYear = calendar().date(from: DateComponents(year: 2026, month: 1, day: 1))!
        XCTAssertEqual(
            MenuBarCompositionPolicy.yearFraction(now: startOfYear, calendar: calendar()), 0, accuracy: 1e-9
        )
    }

    func testYearFractionHandlesLeapYearSpan() {
        // 2028 is a leap year (366 days). Noon on Feb 29 must stay within 0...1
        // and land near the fraction of the full 366-day span.
        let cal = calendar()
        let feb29Noon = cal.date(from: DateComponents(year: 2028, month: 2, day: 29, hour: 12))!
        let fraction = MenuBarCompositionPolicy.yearFraction(now: feb29Noon, calendar: cal)
        // 59.5 days into a 366-day year.
        XCTAssertEqual(fraction, 59.5 / 366.0, accuracy: 1e-4)
    }

    func testProgressFractionDispatchesByStyle() {
        let cal = calendar()
        XCTAssertEqual(
            MenuBarCompositionPolicy.progressFraction(now: now, style: .day, calendar: cal),
            MenuBarCompositionPolicy.dayFraction(now: now, calendar: cal)
        )
        XCTAssertEqual(
            MenuBarCompositionPolicy.progressFraction(now: now, style: .year, calendar: cal),
            MenuBarCompositionPolicy.yearFraction(now: now, calendar: cal)
        )
    }

    // MARK: - weekNumberText

    func testWeekNumberMatchesISOWeek() {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = TimeZone(identifier: "UTC")!
        iso.locale = Locale(identifier: "en_US_POSIX")
        let expected = "W\(iso.component(.weekOfYear, from: now))"
        XCTAssertEqual(
            MenuBarCompositionPolicy.weekNumberText(now: now, calendar: calendar(), prefix: "W"),
            expected
        )
    }

    func testWeekNumberHonorsPrefix() {
        assertMatches(
            MenuBarCompositionPolicy.weekNumberText(now: now, calendar: calendar(), prefix: "KW"),
            "^KW[0-9]{1,2}$"
        )
    }

    // MARK: - worldClockText

    func testWorldClockPinsChosenTimeZone() {
        let utc = MenuBarCompositionPolicy.worldClockText(
            now: now, timeZone: TimeZone(identifier: "UTC")!, label: "", use24Hour: true, calendar: calendar()
        )
        let la = MenuBarCompositionPolicy.worldClockText(
            now: now,
            timeZone: TimeZone(identifier: "America/Los_Angeles")!,
            label: "",
            use24Hour: true,
            calendar: calendar()
        )
        XCTAssertNotEqual(utc, la, "distinct zones should render distinct times")
    }

    func testWorldClockPrependsLabel() {
        let result = MenuBarCompositionPolicy.worldClockText(
            now: now,
            timeZone: TimeZone(identifier: "America/Los_Angeles")!,
            label: "  SF  ",
            use24Hour: true,
            calendar: calendar()
        )
        assertMatches(result, "^SF [0-9]{1,2}:[0-9]{2}$")
    }

    func testWorldClockEmptyLabelYieldsTimeOnly() {
        let result = MenuBarCompositionPolicy.worldClockText(
            now: now, timeZone: TimeZone(identifier: "UTC")!, label: "  ", use24Hour: true, calendar: calendar()
        )
        assertMatches(result, "^[0-9]{1,2}:[0-9]{2}$")
    }

    // MARK: - composedPresentation: new event-independent tokens

    func testComposedRendersProgressWeekWorldClockInEventMode() {
        let result = present(tokens: [.progress, .weekNumber, .worldClock], event: event())
        XCTAssertEqual(result.mode, .nextEvent)
        // Progress bar glyphs present.
        assertMatches(result.title, "[█▏▎▍▌▋▊▉░]")
        // Week number present.
        assertMatches(result.title, "W[0-9]{1,2}")
        // World-clock label present.
        XCTAssertTrue(result.title.contains("SF"), result.title)
    }

    func testComposedRendersNewTokensInNonEventMode() {
        let result = present(tokens: [.icon, .progress, .weekNumber, .worldClock], event: nil)
        XCTAssertEqual(result.mode, .noUpcoming)
        assertMatches(result.title, "[█▏▎▍▌▋▊▉░]")
        assertMatches(result.title, "W[0-9]{1,2}")
        XCTAssertTrue(result.title.contains("SF"), result.title)
        XCTAssertEqual(result.icon, .asset("AppIcon"))
    }
}
