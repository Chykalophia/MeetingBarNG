//
//  TimelineSpanTests.swift
//  MeetingBarLogicTests
//

import XCTest
@testable import MeetingBarLogic

final class TimelineSpanTests: XCTestCase {
    /// 2026-07-28 16:00 local, so "the afternoon" means the same thing in every
    /// assertion below.
    private let now = Calendar.current.date(
        from: DateComponents(year: 2026, month: 7, day: 28, hour: 16)
    )!

    private func hours(_ range: ClosedRange<Date>) -> Double {
        range.upperBound.timeIntervalSince(range.lowerBound) / 3600
    }

    private func offset(_ hoursFromNow: Double) -> Date {
        now.addingTimeInterval(hoursFromNow * 3600)
    }

    // MARK: - Relative

    /// The bug this style was reworked for: at 16:00 with nothing until 19:45,
    /// the fixed -3h window opened on three hours of empty past, so the bar
    /// looked like it started in the middle of nowhere.
    func testRelativeDoesNotOpenOnEmptyPast() {
        let range = DayTimelineRange.range(
            style: .relative,
            now: now,
            bounds: (first: offset(3.75), last: offset(4))
        )
        XCTAssertEqual(
            range.lowerBound,
            now.addingTimeInterval(-DayTimelineRange.minimumLookBehind),
            "with nothing behind us the bar shows the minimum context, not 3h of it"
        )
    }

    /// Trimming the past must not go so far that "now" sits flush against the
    /// leading edge — that reads as clipped rather than as current.
    func testRelativeAlwaysKeepsSomePastOnScreen() {
        for startsIn in [0.25, 1.0, 3.75, 8.0] {
            let range = DayTimelineRange.range(
                style: .relative,
                now: now,
                bounds: (first: offset(startsIn), last: offset(startsIn + 0.5))
            )
            XCTAssertLessThanOrEqual(
                range.lowerBound,
                now.addingTimeInterval(-DayTimelineRange.minimumLookBehind),
                "starting in \(startsIn)h"
            )
        }
    }

    /// It must still open early enough to show a meeting that IS behind us.
    func testRelativeReachesBackForAMeetingAlreadyStarted() {
        let range = DayTimelineRange.range(
            style: .relative,
            now: now,
            bounds: (first: offset(-2), last: offset(1))
        )
        XCTAssertLessThanOrEqual(range.lowerBound, offset(-2))
    }

    /// However far the day reaches, the marker has to be on the bar.
    func testRelativeAlwaysContainsNow() {
        let cases: [(first: Date, last: Date)?] = [
            nil,
            (first: offset(-8), last: offset(-6)),
            (first: offset(5), last: offset(9)),
            (first: offset(0.1), last: offset(0.2))
        ]
        for bounds in cases {
            let range = DayTimelineRange.range(style: .relative, now: now, bounds: bounds)
            XCTAssertTrue(range.contains(now), "\(String(describing: bounds))")
        }
    }

    /// A single short meeting must not collapse the bar around itself.
    func testRelativeKeepsAMinimumSpan() {
        let range = DayTimelineRange.range(
            style: .relative,
            now: now,
            bounds: (first: offset(0.25), last: offset(0.5))
        )
        XCTAssertGreaterThanOrEqual(
            hours(range),
            DayTimelineRange.minimumRelativeSpan / 3600
        )
    }

    /// It never grows past the fixed window, or "around now" stops meaning
    /// anything.
    func testRelativeNeverExceedsTheFixedWindow() {
        let range = DayTimelineRange.range(
            style: .relative,
            now: now,
            bounds: (first: offset(-12), last: offset(12))
        )
        let widest = (DayTimelineRange.relativeLookBehind
            + DayTimelineRange.relativeLookAhead) / 3600
        // Plus the half-hour of breathing room added at each end.
        XCTAssertLessThanOrEqual(hours(range), widest + 1)
    }

    func testRelativeWithNoEventsUsesTheFixedWindow() {
        let range = DayTimelineRange.range(style: .relative, now: now, bounds: nil)
        XCTAssertEqual(range.lowerBound, now.addingTimeInterval(-DayTimelineRange.relativeLookBehind))
        XCTAssertEqual(range.upperBound, now.addingTimeInterval(DayTimelineRange.relativeLookAhead))
    }

    // MARK: - Day

    func testDayCoversTheWorkingDay() {
        let range = DayTimelineRange.range(style: .day, now: now, bounds: nil)
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.hour, from: range.lowerBound), DayTimelineRange.dayStartHour)
        XCTAssertEqual(calendar.component(.hour, from: range.upperBound), DayTimelineRange.dayEndHour)
    }

    /// An early standup or a late call widens the day rather than falling off it.
    func testDayWidensForEventsOutsideWorkingHours() {
        let early = DayTimelineRange.range(
            style: .day,
            now: now,
            bounds: (first: offset(-9.5), last: offset(1))
        )
        XCTAssertLessThanOrEqual(early.lowerBound, offset(-9.5))

        let late = DayTimelineRange.range(
            style: .day,
            now: now,
            bounds: (first: offset(-1), last: offset(6))
        )
        XCTAssertGreaterThanOrEqual(late.upperBound, offset(6))
    }

    func testDayAlwaysContainsNow() {
        // 02:00 — outside the working day entirely.
        let smallHours = Calendar.current.date(
            from: DateComponents(year: 2026, month: 7, day: 28, hour: 2)
        )!
        let range = DayTimelineRange.range(style: .day, now: smallHours, bounds: nil)
        XCTAssertTrue(range.contains(smallHours))
    }

    /// The day style gives a meeting the same place on the bar all day, which is
    /// the property that distinguishes it from the relative one.
    func testDayRangeDoesNotMoveAsTheAfternoonPasses() {
        let bounds = (first: offset(-2), last: offset(2))
        let atFour = DayTimelineRange.range(style: .day, now: now, bounds: bounds)
        let atFive = DayTimelineRange.range(style: .day, now: offset(1), bounds: bounds)
        XCTAssertEqual(atFour, atFive)
    }

    // MARK: - Style

    func testStyleRawValuesAreStableAcrossLaunches() {
        XCTAssertEqual(TimelineSpan.allCases.map(\.rawValue), ["off", "relative", "day"])
    }

    /// `off` is a style rather than a separate toggle, so exactly one control
    /// answers both "is it shown" and "how".
    func testOnlyOffIsHidden() {
        for style in TimelineSpan.allCases {
            XCTAssertEqual(style.isVisible, style != .off, "\(style)")
        }
    }

    /// `.off` never draws, but the range function stays total — a pure function
    /// that traps on a valid case is a crash waiting for a refactor.
    func testOffStillAnswersWithAUsableRange() {
        let range = DayTimelineRange.range(style: .off, now: now, bounds: nil)
        XCTAssertTrue(range.contains(now))
    }

    // MARK: - Migration off the retired toggles

    func testMigrationKeepsTheUpNextCardAsTheCountdownBar() {
        XCTAssertTrue(DropdownModuleMergePolicy.showsProgress(hadUpNextModule: true))
        XCTAssertFalse(DropdownModuleMergePolicy.showsProgress(hadUpNextModule: false))
    }

    func testMigrationTurnsAHiddenTimelineIntoTheOffStyle() {
        XCTAssertEqual(
            DropdownModuleMergePolicy.timelineStyle(wasVisible: false, stored: .day),
            .off
        )
        XCTAssertEqual(
            DropdownModuleMergePolicy.timelineStyle(wasVisible: true, stored: .day),
            .day,
            "a visible timeline keeps whatever style is stored"
        )
    }
}
