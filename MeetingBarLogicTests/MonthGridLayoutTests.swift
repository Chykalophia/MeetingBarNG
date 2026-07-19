//
//  MonthGridLayoutTests.swift
//  MeetingBarLogicTests
//
//  Grid math for the month calendar window: whole weeks respecting
//  firstWeekday, leading/trailing padding from adjacent months, isToday flags,
//  and 5-vs-6 week counts across ordinary, leap, and short months.
//

import XCTest

@testable import MeetingBarLogic

final class MonthGridLayoutTests: XCTestCase {
    /// Deterministic Gregorian calendar in UTC so day math never drifts with the
    /// test machine's locale or timezone. `firstWeekday` is set per test.
    private func makeCalendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)!
    }

    // MARK: - Every row is a full week

    func testEveryWeekHasSevenDays() {
        let calendar = makeCalendar(firstWeekday: 1)
        let july = date(2026, 7, 15, calendar: calendar)
        let weeks = MonthGridLayout.weeks(forMonthContaining: july, calendar: calendar, now: july)
        XCTAssertFalse(weeks.isEmpty)
        for week in weeks {
            XCTAssertEqual(week.count, 7)
        }
    }

    // MARK: - 31-day month (July 2026), Sunday start

    func testJuly2026SundayStartLayout() {
        let calendar = makeCalendar(firstWeekday: 1) // Sunday
        let july = date(2026, 7, 10, calendar: calendar)
        let weeks = MonthGridLayout.weeks(forMonthContaining: july, calendar: calendar, now: july)

        // July 1, 2026 is a Wednesday, so the first row starts on Sun Jun 28.
        let first = weeks.first!.first!
        XCTAssertEqual(first.date, date(2026, 6, 28, calendar: calendar))
        XCTAssertFalse(first.isInMonth)

        // 31 days spilling from a Wednesday needs 5 weeks (35 cells).
        XCTAssertEqual(weeks.count, 5)
        XCTAssertEqual(weeks.flatMap { $0 }.count, 35)

        // Last visible day is Sat Aug 1 (trailing padding).
        let last = weeks.last!.last!
        XCTAssertEqual(last.date, date(2026, 8, 1, calendar: calendar))
        XCTAssertFalse(last.isInMonth)

        // Exactly 31 in-month days.
        XCTAssertEqual(weeks.flatMap { $0 }.filter { $0.isInMonth }.count, 31)
    }

    // MARK: - firstWeekday variations (Monday start)

    func testJuly2026MondayStartShiftsLeadingPadding() {
        let calendar = makeCalendar(firstWeekday: 2) // Monday
        let july = date(2026, 7, 10, calendar: calendar)
        let weeks = MonthGridLayout.weeks(forMonthContaining: july, calendar: calendar, now: july)

        // Monday-start weeks: July 1 (Wed) → first row starts Mon Jun 29.
        let first = weeks.first!.first!
        XCTAssertEqual(first.date, date(2026, 6, 29, calendar: calendar))
        XCTAssertFalse(first.isInMonth)

        // First column is Monday for a Monday-start calendar.
        XCTAssertEqual(calendar.component(.weekday, from: first.date), 2)
        XCTAssertEqual(weeks.flatMap { $0 }.filter { $0.isInMonth }.count, 31)
    }

    // MARK: - Month starting exactly on firstWeekday needs no leading padding

    func testFebruary2026SundayStartNoLeadingPadding() {
        // Feb 1, 2026 is a Sunday; with a Sunday-start week there is no leading
        // padding, so the first cell is Feb 1 itself.
        let calendar = makeCalendar(firstWeekday: 1)
        let february = date(2026, 2, 14, calendar: calendar)
        let weeks = MonthGridLayout.weeks(forMonthContaining: february, calendar: calendar, now: february)

        let first = weeks.first!.first!
        XCTAssertEqual(first.date, date(2026, 2, 1, calendar: calendar))
        XCTAssertTrue(first.isInMonth)
    }

    // MARK: - Leap February (29 days)

    func testFebruary2024IsLeapAndHas29InMonthDays() {
        let calendar = makeCalendar(firstWeekday: 1)
        let february = date(2024, 2, 10, calendar: calendar)
        let weeks = MonthGridLayout.weeks(forMonthContaining: february, calendar: calendar, now: february)

        XCTAssertEqual(weeks.flatMap { $0 }.filter { $0.isInMonth }.count, 29)
        // Feb 29, 2024 must be present and in-month.
        let leapDay = weeks.flatMap { $0 }.first { $0.date == date(2024, 2, 29, calendar: calendar) }
        XCTAssertNotNil(leapDay)
        XCTAssertEqual(leapDay?.isInMonth, true)
    }

    // MARK: - Non-leap February (28 days)

    func testFebruary2025IsNotLeapAndHas28InMonthDays() {
        let calendar = makeCalendar(firstWeekday: 1)
        let february = date(2025, 2, 10, calendar: calendar)
        let weeks = MonthGridLayout.weeks(forMonthContaining: february, calendar: calendar, now: february)

        XCTAssertEqual(weeks.flatMap { $0 }.filter { $0.isInMonth }.count, 28)
        // No in-month day should carry a day-of-month of 29 in a non-leap Feb.
        // (A March-1 cell may still appear as trailing padding — that is correct.)
        XCTAssertFalse(
            weeks.flatMap { $0 }.contains {
                $0.isInMonth && calendar.component(.day, from: $0.date) == 29
            }
        )
    }

    // MARK: - Six-week month

    func testMonthCanSpanSixWeeks() {
        // May 2026 starts on a Friday; a 31-day month spilling from a Friday on a
        // Sunday-start grid needs 6 rows.
        let calendar = makeCalendar(firstWeekday: 1)
        let may = date(2026, 5, 15, calendar: calendar)
        let weeks = MonthGridLayout.weeks(forMonthContaining: may, calendar: calendar, now: may)

        XCTAssertEqual(weeks.count, 6)
        XCTAssertEqual(weeks.flatMap { $0 }.count, 42)
    }

    // MARK: - isToday flag

    func testIsTodayFlagIsSetOnMatchingDayOnly() {
        let calendar = makeCalendar(firstWeekday: 1)
        // now is mid-afternoon on July 17 — isToday must match the whole day.
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 17, hour: 15, minute: 30
        ))!
        let weeks = MonthGridLayout.weeks(
            forMonthContaining: date(2026, 7, 1, calendar: calendar),
            calendar: calendar,
            now: now
        )
        let todays = weeks.flatMap { $0 }.filter { $0.isToday }
        XCTAssertEqual(todays.count, 1)
        XCTAssertEqual(todays.first?.date, date(2026, 7, 17, calendar: calendar))
    }

    func testNoTodayFlagWhenNowIsOutsideVisibleRange() {
        let calendar = makeCalendar(firstWeekday: 1)
        // Viewing July 2026 but "now" is in December — no cell should be today.
        let now = date(2026, 12, 25, calendar: calendar)
        let weeks = MonthGridLayout.weeks(
            forMonthContaining: date(2026, 7, 1, calendar: calendar),
            calendar: calendar,
            now: now
        )
        XCTAssertTrue(weeks.flatMap { $0 }.allSatisfy { !$0.isToday })
    }

    // MARK: - Fetch-range helpers

    func testFirstAndLastVisibleDayBoundTheGrid() {
        let calendar = makeCalendar(firstWeekday: 1)
        let july = date(2026, 7, 10, calendar: calendar)
        let weeks = MonthGridLayout.weeks(forMonthContaining: july, calendar: calendar, now: july)

        XCTAssertEqual(
            MonthGridLayout.firstVisibleDay(forMonthContaining: july, calendar: calendar),
            weeks.first?.first?.date
        )
        XCTAssertEqual(
            MonthGridLayout.lastVisibleDay(forMonthContaining: july, calendar: calendar),
            weeks.last?.last?.date
        )
    }

    func testStartOfMonthNormalizesToFirstDay() {
        let calendar = makeCalendar(firstWeekday: 1)
        let mid = calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 17, hour: 9, minute: 45
        ))!
        XCTAssertEqual(
            MonthGridLayout.startOfMonth(for: mid, calendar: calendar),
            date(2026, 7, 1, calendar: calendar)
        )
    }
}
