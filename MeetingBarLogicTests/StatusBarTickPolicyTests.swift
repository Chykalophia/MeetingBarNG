//
//  StatusBarTickPolicyTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class StatusBarTickPolicyTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-07-21 13:31:54 UTC — the moment of the live report, to the second.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 13, minute: 31, second: 54))!
    }

    private func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: hour, minute: minute, second: second))!
    }

    // MARK: - Minute alignment

    func testNextMinuteBoundaryIsTheStartOfTheFollowingMinute() {
        XCTAssertEqual(
            StatusBarTickPolicy.nextMinuteBoundary(after: now, calendar: calendar),
            at(13, 32)
        )
    }

    /// Exactly on the boundary, the *next* one is a full minute away — not now,
    /// which would spin the timer.
    func testOnTheBoundaryTheNextOneIsAMinuteLater() {
        XCTAssertEqual(
            StatusBarTickPolicy.nextMinuteBoundary(after: at(13, 32), calendar: calendar),
            at(13, 33)
        )
    }

    func testFallsBackToMinuteAlignmentWhenNothingIsScheduled() {
        XCTAssertEqual(
            StatusBarTickPolicy.nextFireDate(now: now, transitions: [], calendar: calendar),
            at(13, 32)
        )
    }

    // MARK: - Transitions

    /// The reported failure: the stand-up starts at 13:30 and, with the grace
    /// period at ten minutes, stops being the current meeting at 13:40. Both
    /// are real redraw points; nothing about the calendar changes at either.
    func testTransitionsCoverStartGraceAndEnd() {
        let transitions = StatusBarTickPolicy.transitionDates(
            eventStart: at(13, 30),
            eventEnd: at(13, 45),
            ongoingGracePeriod: 600
        )
        XCTAssertEqual(Set(transitions), Set([at(13, 30), at(13, 40), at(13, 45)]))
    }

    func testTransitionsOmitTheGracePointWhenThereIsNoGracePeriod() {
        let transitions = StatusBarTickPolicy.transitionDates(
            eventStart: at(13, 30),
            eventEnd: at(13, 45),
            ongoingGracePeriod: nil
        )
        XCTAssertEqual(Set(transitions), Set([at(13, 30), at(13, 45)]))
    }

    func testNoEventYieldsNoTransitions() {
        XCTAssertTrue(
            StatusBarTickPolicy.transitionDates(
                eventStart: nil, eventEnd: nil, ongoingGracePeriod: 600
            ).isEmpty
        )
    }

    /// A transition inside the next minute wins over the minute boundary, so
    /// the redraw lands exactly when the meeting state changes.
    func testAnImminentTransitionBeatsTheMinuteBoundary() {
        XCTAssertEqual(
            StatusBarTickPolicy.nextFireDate(now: at(13, 31, 54), transitions: [at(13, 31, 58)], calendar: calendar),
            at(13, 31, 58)
        )
    }

    func testPastTransitionsAreIgnored() {
        let fire = StatusBarTickPolicy.nextFireDate(
            now: now,
            transitions: [at(13, 30), at(13, 15)],
            calendar: calendar
        )
        XCTAssertEqual(fire, at(13, 32))
    }

    /// A transition an hour out must not defer the redraw an hour — the
    /// countdown still has to advance every minute in the meantime.
    func testDistantTransitionDoesNotDelayTheMinuteTick() {
        XCTAssertEqual(
            StatusBarTickPolicy.nextFireDate(now: now, transitions: [at(14, 30)], calendar: calendar),
            at(13, 32)
        )
    }

    func testNeverSchedulesBeyondTheMaximumInterval() {
        let fire = StatusBarTickPolicy.nextFireDate(now: now, transitions: [at(20, 0)], calendar: calendar)
        XCTAssertLessThanOrEqual(fire.timeIntervalSince(now), StatusBarTickPolicy.maximumInterval)
    }

    // MARK: - Agenda transitions (a whole rendered list, not one meeting)

    func testAgendaTransitionsCoverEveryRowsStartAndEnd() {
        let transitions = StatusBarTickPolicy.transitionDates(
            boundaries: [
                .init(start: at(13, 30), end: at(13, 45)),
                .init(start: at(14, 0), end: at(15, 0))
            ]
        )
        XCTAssertEqual(
            Set(transitions),
            Set([at(13, 30), at(13, 45), at(14, 0), at(15, 0)])
        )
    }

    /// With "hide finished meetings" on, a row also disappears some minutes
    /// after it ends — a third transition per row, and one the list would
    /// otherwise notice up to a minute late.
    func testAgendaTransitionsIncludeTheHideFinishedExpiry() {
        let transitions = StatusBarTickPolicy.transitionDates(
            boundaries: [.init(start: at(13, 30), end: at(13, 45))],
            hideFinishedAfter: 300
        )
        XCTAssertEqual(Set(transitions), Set([at(13, 30), at(13, 45), at(13, 50)]))
    }

    func testAgendaTransitionsOmitTheHideFinishedExpiryWhenFinishedRowsStay() {
        let transitions = StatusBarTickPolicy.transitionDates(
            boundaries: [.init(start: at(13, 30), end: at(13, 45))],
            hideFinishedAfter: nil
        )
        XCTAssertEqual(Set(transitions), Set([at(13, 30), at(13, 45)]))
    }

    func testAnEmptyAgendaYieldsNoTransitions() {
        XCTAssertTrue(
            StatusBarTickPolicy.transitionDates(boundaries: [], hideFinishedAfter: 300).isEmpty
        )
    }

    /// The point of feeding a whole day in: a row further down the list flips to
    /// "running" before the next minute boundary, and the redraw lands on it.
    func testTheEarliestAgendaBoundaryDrivesTheNextFire() {
        let transitions = StatusBarTickPolicy.transitionDates(
            boundaries: [
                .init(start: at(13, 0), end: at(13, 31, 58)),
                .init(start: at(14, 0), end: at(15, 0))
            ]
        )
        XCTAssertEqual(
            StatusBarTickPolicy.nextFireDate(now: now, transitions: transitions, calendar: calendar),
            at(13, 31, 58)
        )
    }

    // MARK: - Delay

    func testDelayIsTheDistanceToTheFireDate() {
        XCTAssertEqual(StatusBarTickPolicy.delay(now: now, until: at(13, 32)), 6, accuracy: 0.001)
    }

    /// Never zero or negative: that would spin, and firing a hair early would
    /// redraw the stale state and then wait a full minute to correct it.
    func testDelayHasAPositiveFloor() {
        XCTAssertEqual(StatusBarTickPolicy.delay(now: now, until: now), 0.5, accuracy: 0.001)
        XCTAssertEqual(
            StatusBarTickPolicy.delay(now: now, until: now.addingTimeInterval(-30)),
            0.5,
            accuracy: 0.001
        )
    }
}
