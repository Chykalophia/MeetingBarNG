//
//  MeetingProgressTests.swift
//  MeetingBarLogicTests
//

import XCTest
@testable import MeetingBarLogic

final class MeetingProgressTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let window: TimeInterval = 3600
    private let lead = 2

    private func presentation(
        startsIn: TimeInterval,
        lasting: TimeInterval = 1800
    ) -> MeetingProgressPresentation? {
        let start = now.addingTimeInterval(startsIn)
        return MeetingProgressPolicy.presentation(
            start: start,
            end: start.addingTimeInterval(lasting),
            now: now,
            leadMinutes: lead,
            window: window
        )
    }

    // MARK: - When nothing is drawn

    func testNothingIsDrawnBeforeTheWindowOpens() {
        XCTAssertNil(presentation(startsIn: window + 1))
        XCTAssertNil(presentation(startsIn: 8 * 3600))
    }

    func testNothingIsDrawnAfterTheMeetingEnds() {
        XCTAssertNil(presentation(startsIn: -3600, lasting: 1800))
    }

    /// The end instant is past, not running — a meeting that just ended must not
    /// leave a full indicator sitting in the menu bar.
    func testNothingIsDrawnAtTheExactEndInstant() {
        XCTAssertNil(presentation(startsIn: -1800, lasting: 1800))
    }

    // MARK: - Filling toward the start

    func testTheIndicatorIsEmptyWhenTheWindowOpens() {
        let result = presentation(startsIn: window)
        XCTAssertEqual(result?.fraction ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(result?.phase, .upcoming)
    }

    func testTheIndicatorIsHalfFullHalfwayThroughTheWindow() {
        XCTAssertEqual(presentation(startsIn: window / 2)?.fraction ?? -1, 0.5, accuracy: 0.0001)
    }

    /// The property the whole design rests on: full means now.
    func testTheIndicatorIsExactlyFullAtTheStartInstant() {
        let result = presentation(startsIn: 0)
        XCTAssertEqual(result?.fraction ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(result?.phase, .running, "the start instant belongs to the meeting")
    }

    func testTheIndicatorIsNearlyFullJustBeforeTheStart() {
        let result = presentation(startsIn: 1)
        XCTAssertGreaterThan(result?.fraction ?? 0, 0.999)
        XCTAssertEqual(result?.phase, .imminent)
    }

    // MARK: - Phase

    func testPhaseBecomesImminentInsideTheSharedThreshold() {
        XCTAssertEqual(presentation(startsIn: TimeInterval(lead) * 60 + 1)?.phase, .upcoming)
        XCTAssertEqual(presentation(startsIn: TimeInterval(lead) * 60)?.phase, .imminent)
        XCTAssertEqual(presentation(startsIn: 30)?.phase, .imminent)
    }

    func testPhaseIsRunningWhileTheMeetingIsOn() {
        XCTAssertEqual(presentation(startsIn: -600, lasting: 1800)?.phase, .running)
    }

    // MARK: - Counting through the meeting

    func testTheIndicatorCountsThroughTheMeeting() {
        XCTAssertEqual(
            presentation(startsIn: -900, lasting: 1800)?.fraction ?? -1,
            0.5,
            accuracy: 0.0001
        )
    }

    /// Calendars really do produce zero-length events; dividing by that duration
    /// would be a crash rather than a cosmetic bug.
    func testZeroLengthMeetingIsCompleteRatherThanDividedByZero() {
        let start = now
        let result = MeetingProgressPolicy.presentation(
            start: start,
            end: start,
            now: now,
            leadMinutes: lead,
            window: window
        )
        // start == end means `now < end` is false, so it is already over.
        XCTAssertNil(result)

        let running = MeetingProgressPolicy.presentation(
            start: now.addingTimeInterval(-1),
            end: now.addingTimeInterval(-1),
            now: now,
            leadMinutes: lead,
            window: window
        )
        XCTAssertNil(running)
    }

    // MARK: - Clamping

    func testFractionIsAlwaysWithinZeroAndOne() {
        XCTAssertEqual(MeetingProgressPresentation(fraction: -5, phase: .upcoming).fraction, 0)
        XCTAssertEqual(MeetingProgressPresentation(fraction: 5, phase: .running).fraction, 1)
    }

    func testAZeroWindowDrawsNothingRatherThanDividingByZero() {
        let start = now.addingTimeInterval(60)
        XCTAssertNil(
            MeetingProgressPolicy.presentation(
                start: start,
                end: start.addingTimeInterval(1800),
                now: now,
                leadMinutes: lead,
                window: 0
            )
        )
    }

    // MARK: - Style

    func testOnlyNoneDrawsNothing() {
        for style in MeetingProgressStyle.allCases {
            XCTAssertEqual(style.drawsSomething, style != .none, "\(style)")
        }
    }

    /// Only the bar costs menu-bar width; the other three are overlays.
    func testOnlyTheBarOccupiesTheImageSlot() {
        for style in MeetingProgressStyle.allCases {
            XCTAssertEqual(style.occupiesImageSlot, style == .bar, "\(style)")
        }
    }

    func testRawValuesAreStableAcrossLaunches() {
        XCTAssertEqual(
            MeetingProgressStyle.allCases.map(\.rawValue),
            ["none", "underline", "ring", "capsule", "bar"]
        )
    }
}
