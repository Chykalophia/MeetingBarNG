//
//  EventListWindowTests.swift
//  MeetingBarLogicTests
//
//  The menu's day list starts at "now": a meeting that ended more than the
//  grace period ago drops off, the in-progress meeting and everything upcoming
//  stay.
//

import XCTest

@testable import MeetingBarLogic

final class EventListWindowTests: XCTestCase {
    // 2026-05-09 06:13:20 UTC — arbitrary fixed reference instant.
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testEndedLongAgoIsDropped() {
        // Ended 10 minutes ago (> 5 min grace).
        XCTAssertFalse(
            EventListWindow.isVisible(endDate: now.addingTimeInterval(-10 * 60), now: now)
        )
    }

    func testEndedWithinGraceIsKept() {
        // Ended 2 minutes ago (< 5 min grace).
        XCTAssertTrue(
            EventListWindow.isVisible(endDate: now.addingTimeInterval(-2 * 60), now: now)
        )
    }

    func testExactlyAtGraceBoundaryIsKept() {
        XCTAssertTrue(
            EventListWindow.isVisible(
                endDate: now.addingTimeInterval(-EventListWindow.endedGracePeriod), now: now
            )
        )
    }

    func testOngoingEventIsKept() {
        // Started earlier, ends in 20 minutes.
        XCTAssertTrue(
            EventListWindow.isVisible(endDate: now.addingTimeInterval(20 * 60), now: now)
        )
    }

    func testUpcomingEventIsKept() {
        XCTAssertTrue(
            EventListWindow.isVisible(endDate: now.addingTimeInterval(3 * 3600), now: now)
        )
    }

    func testTomorrowOrAllDayEventIsKept() {
        // endDate far in the future (tomorrow / all-day) is trivially visible.
        XCTAssertTrue(
            EventListWindow.isVisible(endDate: now.addingTimeInterval(30 * 3600), now: now)
        )
    }
}
