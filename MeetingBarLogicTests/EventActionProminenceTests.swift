//
//  EventActionProminenceTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for whether an event's action control reads as a call to
//  action. Three surfaces share this rule — the panel's event rows, the panel's
//  meeting card, and the classic NSMenu's hosted card — so a change here is
//  visible in all of them at once.
//

import XCTest

@testable import MeetingBarLogic

final class EventActionProminenceTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func minutes(_ count: Double) -> TimeInterval { count * 60 }

    private func imminent(
        startsIn: Double,
        lasting: Double = 30,
        leadMinutes: Int = 2
    ) -> Bool {
        let start = now.addingTimeInterval(minutes(startsIn))
        return EventActionProminence.isImminent(
            start: start,
            end: start.addingTimeInterval(minutes(lasting)),
            now: now,
            leadMinutes: leadMinutes
        )
    }

    // MARK: - Upcoming

    func testMeetingInsideTheLeadWindowIsImminent() {
        XCTAssertTrue(imminent(startsIn: 1))
    }

    func testMeetingExactlyAtTheLeadBoundaryIsImminent() {
        // Inclusive: at exactly two minutes out the button should already be lit,
        // not flip on a moment later.
        XCTAssertTrue(imminent(startsIn: 2))
    }

    func testMeetingBeyondTheLeadWindowIsNot() {
        XCTAssertFalse(imminent(startsIn: 3))
        XCTAssertFalse(imminent(startsIn: 360))
    }

    // MARK: - Running and finished

    func testRunningMeetingIsImminentRegardlessOfLead() {
        // Started 10 minutes ago, 30 long: still going, so still actionable even
        // though it is nowhere near the lead window.
        XCTAssertTrue(imminent(startsIn: -10, leadMinutes: 0))
    }

    func testMeetingStartingExactlyNowIsImminent() {
        XCTAssertTrue(imminent(startsIn: 0))
    }

    func testFinishedMeetingIsNotImminent() {
        // Ended 5 minutes ago. A stale row left open in the panel must recede
        // rather than stay lit indefinitely.
        XCTAssertFalse(imminent(startsIn: -35, lasting: 30))
    }

    func testMeetingEndingExactlyNowIsNoLongerImminent() {
        XCTAssertFalse(imminent(startsIn: -30, lasting: 30))
    }

    // MARK: - Lead configuration

    func testZeroLeadMeansOnlyWhileRunning() {
        XCTAssertFalse(imminent(startsIn: 1, leadMinutes: 0))
        XCTAssertTrue(imminent(startsIn: -1, leadMinutes: 0))
    }

    func testNegativeLeadIsClampedRatherThanInverted() {
        // A corrupt or hand-edited preference must degrade to "only while
        // running", never light up everything by flipping the comparison.
        XCTAssertFalse(imminent(startsIn: 1, leadMinutes: -60))
        XCTAssertFalse(imminent(startsIn: 120, leadMinutes: -60))
        XCTAssertTrue(imminent(startsIn: -1, leadMinutes: -60))
    }

    func testLargeLeadLightsUpDistantMeetings() {
        XCTAssertTrue(imminent(startsIn: 90, leadMinutes: 120))
    }
}
