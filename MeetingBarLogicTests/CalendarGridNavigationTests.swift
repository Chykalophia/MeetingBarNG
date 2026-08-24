//
//  CalendarGridNavigationTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for arrow-key travel in the calendar window (MeetingBarNG):
//  where the selection lands, and when the grid has to page to follow it.
//

import XCTest

@testable import MeetingBarLogic

final class CalendarGridNavigationTests: XCTestCase {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar().date(from: components)!
    }

    /// August 2026 as a month grid draws 26 Jul – 5 Sep once padding is included.
    private var augustVisible: (start: Date, end: Date) {
        (date(2026, 7, 26), date(2026, 9, 5))
    }

    private func move(_ from: Date, _ days: Int, range: (start: Date, end: Date)? = nil)
        -> CalendarGridNavigationResult {
        CalendarGridNavigation.move(
            from: from,
            byDays: days,
            visibleRange: range ?? augustVisible,
            calendar: calendar()
        )
    }

    // MARK: - Where the selection lands

    func testLeftAndRightMoveOneDay() {
        XCTAssertEqual(
            move(date(2026, 8, 15), CalendarGridNavigation.nextDay).selectedDay,
            calendar().startOfDay(for: date(2026, 8, 16))
        )
        XCTAssertEqual(
            move(date(2026, 8, 15), CalendarGridNavigation.previousDay).selectedDay,
            calendar().startOfDay(for: date(2026, 8, 14))
        )
    }

    func testUpAndDownMoveOneWeek() {
        // A grid row IS a week, so Up must land in the cell directly above.
        XCTAssertEqual(
            move(date(2026, 8, 15), CalendarGridNavigation.nextWeek).selectedDay,
            calendar().startOfDay(for: date(2026, 8, 22))
        )
        XCTAssertEqual(
            move(date(2026, 8, 15), CalendarGridNavigation.previousWeek).selectedDay,
            calendar().startOfDay(for: date(2026, 8, 8))
        )
    }

    func testResultIsNormalisedToStartOfDay() {
        // The caller may hold a selection with a time on it; the grid deals in days.
        let result = move(date(2026, 8, 15), 0)
        XCTAssertEqual(result.selectedDay, calendar().startOfDay(for: date(2026, 8, 15)))
    }

    func testMovingAcrossAMonthBoundaryLandsOnTheRealDate() {
        XCTAssertEqual(
            move(date(2026, 8, 31), CalendarGridNavigation.nextDay).selectedDay,
            calendar().startOfDay(for: date(2026, 9, 1))
        )
    }

    func testMovingAcrossAYearBoundary() {
        let range = (date(2026, 12, 27), date(2027, 1, 30))
        XCTAssertEqual(
            move(date(2026, 12, 31), CalendarGridNavigation.nextDay, range: range).selectedDay,
            calendar().startOfDay(for: date(2027, 1, 1))
        )
    }

    // MARK: - Paging

    func testStayingInsideTheVisibleRangeDoesNotPage() {
        XCTAssertFalse(move(date(2026, 8, 15), CalendarGridNavigation.nextWeek).requiresPaging)
    }

    func testPaddingDaysFromAdjacentMonthsDoNotPage() {
        // 1 Sep is drawn as a padding cell in the August grid. Selecting a cell
        // that is visibly on screen must not scroll the grid out from under the
        // user.
        let result = move(date(2026, 8, 31), CalendarGridNavigation.nextDay)
        XCTAssertFalse(result.requiresPaging)
    }

    func testTheLastDrawnDayIsInclusive() {
        // 5 Sep is the final padding cell; landing exactly on it is still visible.
        let result = move(date(2026, 9, 4), CalendarGridNavigation.nextDay)
        XCTAssertEqual(result.selectedDay, calendar().startOfDay(for: date(2026, 9, 5)))
        XCTAssertFalse(result.requiresPaging)
    }

    func testTheFirstDrawnDayIsInclusive() {
        let result = move(date(2026, 7, 27), CalendarGridNavigation.previousDay)
        XCTAssertEqual(result.selectedDay, calendar().startOfDay(for: date(2026, 7, 26)))
        XCTAssertFalse(result.requiresPaging)
    }

    func testWalkingOffTheEndPages() {
        XCTAssertTrue(move(date(2026, 9, 5), CalendarGridNavigation.nextDay).requiresPaging)
    }

    func testWalkingOffTheStartPages() {
        XCTAssertTrue(move(date(2026, 7, 26), CalendarGridNavigation.previousDay).requiresPaging)
    }

    func testJumpingAWholeWeekPastTheEdgePages() {
        XCTAssertTrue(move(date(2026, 9, 3), CalendarGridNavigation.nextWeek).requiresPaging)
    }

    // MARK: - Week mode

    func testInAWeekGridAnyVerticalMoveLeavesTheRow() {
        // A folded week is one row, so Up or Down always pages by definition.
        let week = (date(2026, 8, 9), date(2026, 8, 15))
        XCTAssertTrue(
            move(date(2026, 8, 12), CalendarGridNavigation.nextWeek, range: week).requiresPaging
        )
        XCTAssertTrue(
            move(date(2026, 8, 12), CalendarGridNavigation.previousWeek, range: week).requiresPaging
        )
        XCTAssertFalse(
            move(date(2026, 8, 12), CalendarGridNavigation.nextDay, range: week).requiresPaging
        )
    }
}
