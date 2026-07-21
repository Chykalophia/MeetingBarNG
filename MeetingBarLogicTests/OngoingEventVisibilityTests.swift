//
//  OngoingEventVisibilityTests.swift
//  MeetingBarLogicTests
//
//  Regression coverage for "Hide the current meeting from the menu bar".
//  Reported live: with the setting on "10 minutes after it starts", a meeting
//  that had *just* started was already gone, so there was no way to join the
//  meeting the user was supposed to be in.
//

import XCTest

@testable import MeetingBarLogic

final class OngoingEventVisibilityTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func settings(
        _ visibility: EventSelectionOngoingVisibility,
        includesPersonalEvents: Bool = true,
        hidesTentativeEvents: Bool = false,
        hidesPendingEvents: Bool = false
    ) -> EventSelectionSettings {
        EventSelectionSettings(
            period: .todayAndTomorrow,
            includesPersonalEvents: includesPersonalEvents,
            dismissedEvents: [],
            requiresMeetingLinkForNonAllDayEvents: false,
            hidesPendingEvents: hidesPendingEvents,
            hidesTentativeEvents: hidesTentativeEvents,
            ongoingEventVisibility: visibility
        )
    }

    private func event(
        id: String,
        startsIn: TimeInterval,
        duration: TimeInterval = 1800,
        hasMeetingLink: Bool = true,
        hasAttendees: Bool = true,
        participationStatus: EventSelectionEvent.ParticipationStatus = .active
    ) -> EventSelectionEvent {
        EventSelectionEvent(
            sourceIndex: 0,
            id: id,
            lastModifiedDate: nil,
            startDate: now.addingTimeInterval(startsIn),
            endDate: now.addingTimeInterval(startsIn + duration),
            isAllDay: false,
            hasMeetingLink: hasMeetingLink,
            hasAttendees: hasAttendees,
            status: .active,
            participationStatus: participationStatus
        )
    }

    private func selected(
        _ events: [EventSelectionEvent],
        _ settings: EventSelectionSettings
    ) -> String? {
        EventSelection.nextEvent(
            from: events,
            linkRequired: false,
            settings: settings,
            now: now
        )?.id
    }

    private func selected(
        _ events: [EventSelectionEvent],
        _ visibility: EventSelectionOngoingVisibility
    ) -> String? {
        selected(events, settings(visibility))
    }

    // MARK: - "10 minutes after it starts"

    /// The reported failure: a meeting ~2 minutes in must still be selected.
    func testMeetingThatJustStartedIsStillSelected() {
        let running = event(id: "running", startsIn: -120)
        XCTAssertEqual(selected([running], .showTenMinAfter), "running")
    }

    func testMeetingStaysSelectedRightUpToTheTenMinuteMark() {
        let running = event(id: "running", startsIn: -599)
        XCTAssertEqual(selected([running], .showTenMinAfter), "running")
    }

    func testMeetingIsDroppedOnceTenMinutesHavePassed() {
        let running = event(id: "running", startsIn: -600)
        XCTAssertNil(selected([running], .showTenMinAfter))
    }

    /// With a later meeting queued, the running one still wins for the first
    /// ten minutes — otherwise "Join" points at the wrong meeting.
    func testRunningMeetingBeatsALaterOneWithinTenMinutes() {
        let events = [event(id: "running", startsIn: -120), event(id: "later", startsIn: 3600)]
        XCTAssertEqual(selected(events, .showTenMinAfter), "running")
    }

    func testLaterMeetingTakesOverAfterTenMinutes() {
        let events = [event(id: "running", startsIn: -600), event(id: "later", startsIn: 3600)]
        XCTAssertEqual(selected(events, .showTenMinAfter), "later")
    }

    // MARK: - The reported day, reproduced exactly

    /// The real schedule at the moment of the report: a 15-minute stand-up that
    /// began 114 seconds earlier, the huddle that ended as it began, and the
    /// next meeting an hour out. The stand-up must be selected.
    func testReportedSchedulePicksTheStandUpThatJustStarted() {
        let events = [
            event(id: "clarity-break", startsIn: -1914, duration: 900, hasMeetingLink: false, hasAttendees: false),
            event(id: "huddle", startsIn: -1014, duration: 900),
            event(id: "standup", startsIn: -114, duration: 900),
            event(id: "caredocs", startsIn: 3486, duration: 2400)
        ]
        XCTAssertEqual(selected(events, .showTenMinAfter), "standup")
    }

    /// A 15-minute meeting is shorter than the 10-minute grace period, so the
    /// window in which it can be selected is real but narrow. It must survive
    /// right up to the moment the grace period expires.
    func testShortMeetingSurvivesUntilTheGracePeriodExpires() {
        let standup = event(id: "standup", startsIn: -599, duration: 900)
        XCTAssertEqual(selected([standup], .showTenMinAfter), "standup")
    }

    // MARK: - The hidden coupling: "show as inactive" also de-selects

    /// Documents today's behaviour rather than endorsing it: choosing
    /// "show as inactive" for tentative invites ALSO removes them from
    /// next-event selection, so an in-progress tentative meeting cannot be
    /// joined from the menu bar. The label only ever described styling.
    func testInactiveTentativeIsAlsoRemovedFromSelection() {
        let running = event(id: "running", startsIn: -120, participationStatus: .tentative)
        XCTAssertNil(selected([running], settings(.showTenMinAfter, hidesTentativeEvents: true)))
        XCTAssertEqual(
            selected([running], settings(.showTenMinAfter, hidesTentativeEvents: false)),
            "running"
        )
    }

    // MARK: - The other two modes, so the fix cannot regress them

    func testHideImmediatelyDropsARunningMeeting() {
        let running = event(id: "running", startsIn: -60)
        XCTAssertNil(selected([running], .hideImmediateAfter))
    }

    func testHideImmediatelyKeepsAMeetingThatHasNotStarted() {
        let soon = event(id: "soon", startsIn: 60)
        XCTAssertEqual(selected([soon], .hideImmediateAfter), "soon")
    }

    /// `.showTenMinBeforeNext` keeps the running meeting until the next one is
    /// within ten minutes, at which point the next one takes over.
    func testShowUntilNextIsCloseKeepsTheRunningMeeting() {
        let events = [
            event(id: "running", startsIn: -1800, duration: 3600),
            event(id: "later", startsIn: 3600)
        ]
        XCTAssertEqual(selected(events, .showTenMinBeforeNext), "running")
    }

    func testShowUntilNextIsCloseHandsOverWhenTheNextIsImminent() {
        let events = [
            event(id: "running", startsIn: -1800, duration: 3600),
            event(id: "next", startsIn: 300)
        ]
        XCTAssertEqual(selected(events, .showTenMinBeforeNext), "next")
    }
}
