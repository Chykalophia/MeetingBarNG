//
//  DaySummaryPolicyTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for the day-summary greeting policy (MeetingBarNG).
//

import XCTest

@testable import MeetingBarLogic

final class DaySummaryPolicyTests: XCTestCase {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 15) -> Date {
        calendar().date(from: DateComponents(year: 2026, month: 7, day: day, hour: hour, minute: minute))!
    }

    private func interval(_ startHour: Int, _ endHour: Int, day: Int = 15) -> DaySummaryInterval {
        DaySummaryInterval(start: date(startHour, day: day), end: date(endHour, day: day), isAllDay: false)
    }

    private func allDay(day: Int = 15) -> DaySummaryInterval {
        DaySummaryInterval(start: date(0, day: day), end: date(0, day: day + 1), isAllDay: true)
    }

    // MARK: - time of day

    func testTimeOfDayBoundaries() {
        XCTAssertEqual(DaySummaryPolicy.timeOfDay(now: date(0), calendar: calendar()), .morning)
        XCTAssertEqual(DaySummaryPolicy.timeOfDay(now: date(11, 59), calendar: calendar()), .morning)
        XCTAssertEqual(DaySummaryPolicy.timeOfDay(now: date(12), calendar: calendar()), .afternoon)
        XCTAssertEqual(DaySummaryPolicy.timeOfDay(now: date(16, 59), calendar: calendar()), .afternoon)
        XCTAssertEqual(DaySummaryPolicy.timeOfDay(now: date(17), calendar: calendar()), .evening)
        XCTAssertEqual(DaySummaryPolicy.timeOfDay(now: date(23, 59), calendar: calendar()), .evening)
    }

    // MARK: - event count

    func testEventCountExcludesAllDay() {
        let summary = DaySummaryPolicy.summary(
            input: DaySummaryInput(now: date(9), events: [interval(10, 11), interval(14, 15), allDay()]),
            calendar: calendar()
        )
        XCTAssertEqual(summary.eventCount, 2)
    }

    func testEventCountZeroForEmptyDay() {
        let summary = DaySummaryPolicy.summary(
            input: DaySummaryInput(now: date(9), events: []),
            calendar: calendar()
        )
        XCTAssertEqual(summary.eventCount, 0)
    }

    // MARK: - free minutes

    func testFreeMinutesEmptyDayIsRemainderOfDay() {
        // 09:00 → midnight = 15 h.
        XCTAssertEqual(
            DaySummaryPolicy.freeMinutes(now: date(9), events: [], calendar: calendar()), 15 * 60
        )
    }

    func testFreeMinutesSubtractsSingleMeeting() {
        XCTAssertEqual(
            DaySummaryPolicy.freeMinutes(now: date(9), events: [interval(10, 11)], calendar: calendar()),
            15 * 60 - 60
        )
    }

    func testFreeMinutesMergesOverlappingMeetings() {
        // 10–12 and 11–13 merge to 10–13 = 180 min covered.
        XCTAssertEqual(
            DaySummaryPolicy.freeMinutes(
                now: date(9), events: [interval(10, 12), interval(11, 13)], calendar: calendar()
            ),
            15 * 60 - 180
        )
    }

    func testFreeMinutesMergesAdjacentMeetings() {
        // 10–11 and 11–12 are adjacent → 120 min covered, not double counted.
        XCTAssertEqual(
            DaySummaryPolicy.freeMinutes(
                now: date(9), events: [interval(10, 11), interval(11, 12)], calendar: calendar()
            ),
            15 * 60 - 120
        )
    }

    func testFreeMinutesClampsFullyPastMeeting() {
        // Meeting entirely before now contributes nothing; window is 14:00→24:00.
        XCTAssertEqual(
            DaySummaryPolicy.freeMinutes(now: date(14), events: [interval(10, 11)], calendar: calendar()),
            10 * 60
        )
    }

    func testFreeMinutesClampsMeetingStraddlingNow() {
        // now 10:30, meeting 10:00–11:00 → only 30 min counts.
        XCTAssertEqual(
            DaySummaryPolicy.freeMinutes(now: date(10, 30), events: [interval(10, 11)], calendar: calendar()),
            13 * 60 + 30 - 30
        )
    }

    func testFreeMinutesClampsMeetingRunningPastMidnight() {
        // now 22:00, meeting 23:00→01:00 next day → only 23:00–24:00 counts.
        let meeting = DaySummaryInterval(start: date(23, day: 15), end: date(1, day: 16), isAllDay: false)
        XCTAssertEqual(
            DaySummaryPolicy.freeMinutes(now: date(22), events: [meeting], calendar: calendar()),
            60
        )
    }

    func testFreeMinutesFullyBookedIsZero() {
        let meeting = DaySummaryInterval(start: date(9, day: 15), end: date(0, day: 16), isAllDay: false)
        XCTAssertEqual(
            DaySummaryPolicy.freeMinutes(now: date(9), events: [meeting], calendar: calendar()),
            0
        )
    }

    func testFreeMinutesIgnoresAllDayEvents() {
        XCTAssertEqual(
            DaySummaryPolicy.freeMinutes(now: date(9), events: [allDay()], calendar: calendar()),
            15 * 60
        )
    }

    // MARK: - end-to-end summary

    func testSummaryCombinesAllFields() {
        let summary = DaySummaryPolicy.summary(
            input: DaySummaryInput(
                now: date(9),
                events: [interval(10, 11), interval(14, 15), allDay()]
            ),
            calendar: calendar()
        )
        XCTAssertEqual(summary.timeOfDay, .morning)
        XCTAssertEqual(summary.eventCount, 2)
        XCTAssertEqual(summary.freeMinutes, 15 * 60 - 120)
    }
}
