//
//  StatusBarPresentationTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class StatusBarPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let assets = StatusBarIconAssets(
        appIcon: "AppIcon",
        calendarCheckmark: "iconCalendarCheckmark",
        calendar: "iconCalendar"
    )

    private func settings(
        hasSelectedCalendars: Bool = true,
        showEventMaxTimeUntilEventEnabled: Bool = false,
        threshold: Int = 30,
        highlightImminentEvent: Bool = true,
        imminentLeadMinutes: Int = 2
    ) -> StatusBarPresentationSettings {
        StatusBarPresentationSettings(
            hasSelectedCalendars: hasSelectedCalendars,
            showEventMaxTimeUntilEventEnabled: showEventMaxTimeUntilEventEnabled,
            showEventMaxTimeUntilEventThreshold: threshold,
            highlightImminentEvent: highlightImminentEvent,
            imminentLeadMinutes: imminentLeadMinutes
        )
    }

    private func presenterSettings(
        hasSelectedCalendars: Bool = true,
        titleFormat: StatusBarEventTitleFormat = .show,
        titleLength: Int = 55,
        timeDisplay: StatusBarTimeDisplay = .show,
        iconFormat: StatusBarIconFormat = .none,
        pendingDisplay: StatusBarParticipationDisplay = .normal,
        tentativeDisplay: StatusBarParticipationDisplay = .normal,
        highlightImminentEvent: Bool = true,
        imminentLeadMinutes: Int = 2
    ) -> StatusBarPresenterSettings {
        StatusBarPresenterSettings(
            presentation: settings(
                hasSelectedCalendars: hasSelectedCalendars,
                highlightImminentEvent: highlightImminentEvent,
                imminentLeadMinutes: imminentLeadMinutes
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
            timeDisplay: timeDisplay,
            iconFormat: iconFormat,
            iconFormatAssetName: "no_online_session",
            iconAssets: assets,
            pendingDisplay: pendingDisplay,
            tentativeDisplay: tentativeDisplay
        )
    }

    private func event(
        title: String? = "Weekly sync",
        meetingService: MeetingServices? = .zoom,
        participation: StatusBarEventParticipation = .normal,
        startsIn: TimeInterval = 600,
        lasting: TimeInterval = 1800
    ) -> StatusBarEventPresentationInput {
        StatusBarEventPresentationInput(
            title: title,
            startDate: now.addingTimeInterval(startsIn),
            endDate: now.addingTimeInterval(startsIn + lasting),
            meetingService: meetingService,
            participation: participation
        )
    }

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    func testIdleWhenNoCalendarsSelected() {
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: now.addingTimeInterval(60),
            settings: settings(hasSelectedCalendars: false),
            now: now
        )
        XCTAssertEqual(
            mode, .idle,
            "no calendars selected → idle regardless of any next event")
    }

    func testNoUpcomingWhenSelectedButNoEvent() {
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: nil,
            settings: settings(),
            now: now
        )
        XCTAssertEqual(mode, .noUpcoming)
    }

    func testNextEventWhenThresholdDisabled() {
        // Even an event 12 hours away renders as "next" when the threshold
        // toggle is off — that is the legacy default behavior.
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: now.addingTimeInterval(43_200),
            settings: settings(showEventMaxTimeUntilEventEnabled: false),
            now: now
        )
        XCTAssertEqual(mode, .nextEvent)
    }

    func testNextEventWhenWithinThreshold() {
        // Threshold 30 min, event 10 min away → within threshold → render
        // as next event with title.
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: now.addingTimeInterval(600),
            settings: settings(showEventMaxTimeUntilEventEnabled: true, threshold: 30),
            now: now
        )
        XCTAssertEqual(mode, .nextEvent)
    }

    func testAfterThresholdWhenBeyondThreshold() {
        // Threshold 30 min, event 45 min away → past threshold → alarm hint.
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: now.addingTimeInterval(2700),
            settings: settings(showEventMaxTimeUntilEventEnabled: true, threshold: 30),
            now: now
        )
        XCTAssertEqual(mode, .afterThreshold)
    }

    func testOngoingEventCountsAsNextEvent() {
        // An event that started 5 min ago (timeUntilStart < 0) is below
        // any positive threshold and should render as the current next event.
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: now.addingTimeInterval(-300),
            settings: settings(showEventMaxTimeUntilEventEnabled: true, threshold: 30),
            now: now
        )
        XCTAssertEqual(
            mode, .nextEvent,
            "negative timeUntilStart is always within any positive threshold")
    }

    func testThresholdBoundaryIsExclusive() {
        // Threshold 30 min, event exactly 30 min away → not strictly less
        // than the threshold → afterThreshold. Documents the existing
        // boundary semantics inherited from updateTitle().
        let mode = StatusBarPresentationPolicy.mode(
            nextEventStartDate: now.addingTimeInterval(1800),
            settings: settings(showEventMaxTimeUntilEventEnabled: true, threshold: 30),
            now: now
        )
        XCTAssertEqual(mode, .afterThreshold)
    }

    func testPresenterPreservesRTLTitleWithInlineTime() {
        let presentation = StatusBarPresenter.presentation(
            nextEvent: event(title: "פגישת צוות"),
            settings: presenterSettings(timeDisplay: .show),
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.title, "פגישת צוות")
        XCTAssertEqual(presentation.layout, .inline(showTime: true))
    }

    func testPresenterUsesStackedLayoutForTimeUnderTitle() {
        let presentation = StatusBarPresenter.presentation(
            nextEvent: event(),
            settings: presenterSettings(timeDisplay: .showUnderTitle),
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.layout, .stacked)
        XCTAssertFalse(presentation.time.isEmpty)
    }

    func testPresenterKeepsFullTitleAndOmitsIconWhenIconDisabled() {
        let longTitle = String(repeating: "Very long meeting title ", count: 8)
        let presentation = StatusBarPresenter.presentation(
            nextEvent: event(title: longTitle, meetingService: .zoom),
            settings: presenterSettings(titleLength: 200, iconFormat: .none),
            now: now,
            calendar: calendar()
        )

        // No icon was selected, so the presenter must not inject a meeting-service
        // icon, and the title must honor the configured length (no compaction).
        XCTAssertEqual(presentation.icon, .none)
        XCTAssertEqual(presentation.title, longTitle.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testPresenterHonorsHiddenTitleWhenIconIsDisabled() {
        let presentation = StatusBarPresenter.presentation(
            nextEvent: event(title: "Weekly sync", meetingService: nil),
            settings: presenterSettings(titleFormat: .none, timeDisplay: .hide, iconFormat: .none),
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.title, "")
        XCTAssertEqual(presentation.icon, .none)
        XCTAssertEqual(presentation.layout, .inline(showTime: false))
    }

    func testPresenterMarksPendingStackedTitleInactive() {
        let presentation = StatusBarPresenter.presentation(
            nextEvent: event(participation: .pending),
            settings: presenterSettings(timeDisplay: .showUnderTitle, pendingDisplay: .inactive),
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.titleStyle, .inactive)
    }

    // MARK: - Non-event modes (guard mode == .nextEvent, let nextEvent else)

    func testPresenterReturnsEmptyPresentationForIdleMode() {
        // hasSelectedCalendars: false → mode = .idle → guard fires
        let presentation = StatusBarPresenter.presentation(
            nextEvent: event(),
            settings: presenterSettings(hasSelectedCalendars: false),
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.mode, .idle)
        XCTAssertEqual(presentation.title, "")
        XCTAssertEqual(presentation.time, "")
        XCTAssertNil(presentation.tooltip)
        XCTAssertEqual(presentation.layout, .none)
        XCTAssertFalse(presentation.removeDeliveredNotifications)
    }

    func testPresenterReturnsEmptyPresentationForNoUpcomingMode() {
        // nil nextEvent → mode = .noUpcoming; removeDeliveredNotifications must be true
        let presentation = StatusBarPresenter.presentation(
            nextEvent: nil,
            settings: presenterSettings(),
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.mode, .noUpcoming)
        XCTAssertEqual(presentation.title, "")
        XCTAssertTrue(
            presentation.removeDeliveredNotifications,
            "noUpcoming mode should trigger removal of delivered notifications")
    }

    func testPresenterReturnsEmptyPresentationForAfterThresholdMode() {
        // event 60 min away, threshold 30 min → mode = .afterThreshold → guard fires
        let base = presenterSettings()
        let settings = StatusBarPresenterSettings(
            presentation: StatusBarPresentationSettings(
                hasSelectedCalendars: true,
                showEventMaxTimeUntilEventEnabled: true,
                showEventMaxTimeUntilEventThreshold: 30
            ),
            title: base.title,
            timeDisplay: base.timeDisplay,
            iconFormat: base.iconFormat,
            iconFormatAssetName: base.iconFormatAssetName,
            iconAssets: base.iconAssets,
            pendingDisplay: base.pendingDisplay,
            tentativeDisplay: base.tentativeDisplay
        )
        let farEvent = StatusBarEventPresentationInput(
            title: "Far meeting",
            startDate: now.addingTimeInterval(3600),  // 60 min away
            endDate: now.addingTimeInterval(5400),
            meetingService: .zoom,
            participation: .normal
        )
        let presentation = StatusBarPresenter.presentation(
            nextEvent: farEvent,
            settings: settings,
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.mode, .afterThreshold)
        XCTAssertEqual(presentation.title, "")
        XCTAssertFalse(presentation.removeDeliveredNotifications)
    }

    // MARK: - titleStyle: tentative + underlined

    func testPresenterTentativeWithUnderlinedDisplayStyleIsUnderlined() {
        let presentation = StatusBarPresenter.presentation(
            nextEvent: event(participation: .tentative),
            settings: presenterSettings(tentativeDisplay: .underlined),
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.titleStyle, .underlined)
    }

    // MARK: - titleLayout: titleFormat .none + timeDisplay .showUnderTitle

    func testPresenterTitleFormatNoneWithTimeUnderTitleUsesInlineNoTime() {
        // titleFormat == .none AND timeDisplay == .showUnderTitle
        // → titleLayout exits early via guard and returns .inline(showTime: false)
        let presentation = StatusBarPresenter.presentation(
            nextEvent: event(),
            settings: presenterSettings(titleFormat: .none, timeDisplay: .showUnderTitle),
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.layout, .inline(showTime: false))
    }

    // MARK: - titleLayout: titleFormat .show + timeDisplay .hide

    func testPresenterShowTitleWithHideTimeUsesInlineNoTime() {
        // titleFormat != .none AND timeDisplay == .hide
        // → titleLayout switch case .hide: return .inline(showTime: false)
        let presentation = StatusBarPresenter.presentation(
            nextEvent: event(),
            settings: presenterSettings(titleFormat: .show, timeDisplay: .hide),
            now: now,
            calendar: calendar()
        )

        XCTAssertEqual(presentation.layout, .inline(showTime: false))
    }

    // MARK: - Emphasis when the meeting is about to start
    //
    // The menu bar has no button to mute, so the dropdown's "is this actionable
    // yet" signal shows up here as weight instead: normal all day, heavier once
    // the meeting is within the shared lead window.

    private func emphasis(
        startsIn: TimeInterval,
        lasting: TimeInterval = 1800,
        participation: StatusBarEventParticipation = .normal,
        enabled: Bool = true,
        leadMinutes: Int = 2,
        pendingDisplay: StatusBarParticipationDisplay = .normal,
        timeDisplay: StatusBarTimeDisplay = .show
    ) -> Bool {
        StatusBarPresenter.presentation(
            nextEvent: event(
                participation: participation,
                startsIn: startsIn,
                lasting: lasting
            ),
            settings: presenterSettings(
                timeDisplay: timeDisplay,
                pendingDisplay: pendingDisplay,
                highlightImminentEvent: enabled,
                imminentLeadMinutes: leadMinutes
            ),
            now: now,
            calendar: calendar()
        ).emphasizeTitle
    }

    func testTitleIsNotEmphasisedWhileTheMeetingIsStillAWayOff() {
        XCTAssertFalse(emphasis(startsIn: 600))
    }

    func testTitleIsEmphasisedInsideTheLeadWindow() {
        XCTAssertTrue(emphasis(startsIn: 60))
    }

    func testTitleIsEmphasisedWhileTheMeetingIsRunning() {
        XCTAssertTrue(emphasis(startsIn: -300))
    }

    func testTitleIsNotEmphasisedOnceTheMeetingHasEnded() {
        XCTAssertFalse(emphasis(startsIn: -3600, lasting: 1800))
    }

    func testEmphasisRespectsTheToggle() {
        XCTAssertFalse(emphasis(startsIn: 60, enabled: false))
    }

    func testEmphasisFollowsTheSharedLeadSetting() {
        // 30 minutes out is not imminent at the default lead, but is at 60.
        XCTAssertFalse(emphasis(startsIn: 1800, leadMinutes: 2))
        XCTAssertTrue(emphasis(startsIn: 1800, leadMinutes: 60))
    }

    /// A pending meeting rendered inactive is dimmed precisely because it is not
    /// yet yours; shouting about it a minute beforehand would argue with that.
    ///
    /// Stacked layout on purpose — `titleStyle` only resolves `.inactive` there
    /// (inline keeps `.normal`), so this is the only layout where a meeting is
    /// actually dimmed and the interaction can be observed at all.
    func testADimmedMeetingIsNeverEmphasised() {
        XCTAssertFalse(
            emphasis(
                startsIn: 60,
                participation: .pending,
                pendingDisplay: .inactive,
                timeDisplay: .showUnderTitle
            )
        )
    }

    func testANormalMeetingIsStillEmphasisedWhenPendingsAreDimmed() {
        // Guards the rule above against over-reach: dimming pendings must not
        // switch emphasis off for everyone else.
        XCTAssertTrue(
            emphasis(
                startsIn: 60,
                participation: .normal,
                pendingDisplay: .inactive,
                timeDisplay: .showUnderTitle
            )
        )
    }

    /// In inline layout a pending meeting is NOT dimmed (`titleStyle` returns
    /// `.normal`), so emphasis is consistent with how it already looks. Pins that
    /// asymmetry so it is a decision rather than a surprise.
    func testAPendingMeetingIsEmphasisedInInlineLayoutWhereItIsNotDimmed() {
        XCTAssertTrue(
            emphasis(startsIn: 60, participation: .pending, pendingDisplay: .inactive)
        )
    }
}
