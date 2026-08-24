//
//  MonthWeekFoldTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for the compact calendar's month/week fold (MeetingBarNG):
//  what a step means in each mode, what rows come back, and the range a title
//  can honestly claim.
//

import XCTest

@testable import MeetingBarLogic

final class MonthWeekFoldTests: XCTestCase {
    private func calendar(firstWeekday: Int = 1) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = firstWeekday
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

    private func day(_ date: Date) -> Int {
        calendar().component(.day, from: date)
    }

    private func month(_ date: Date) -> Int {
        calendar().component(.month, from: date)
    }

    // MARK: - Stepping

    func testMonthFoldStepsByMonths() {
        let now = date(2026, 8, 15)
        let next = MonthGridLayout.anchor(from: now, offset: 1, isWeekFold: false, calendar: calendar())
        XCTAssertEqual(month(next), 9)
    }

    func testWeekFoldStepsByWeeks() {
        // Paging a week view by a whole month would skip four weeks of the thing
        // being looked at — the step unit has to follow the fold.
        let now = date(2026, 8, 15)
        let next = MonthGridLayout.anchor(from: now, offset: 1, isWeekFold: true, calendar: calendar())
        XCTAssertEqual(month(next), 8)
        XCTAssertEqual(day(next), 22)
    }

    func testSteppingBackwardsWorksInBothFolds() {
        let now = date(2026, 8, 15)
        XCTAssertEqual(
            month(MonthGridLayout.anchor(from: now, offset: -1, isWeekFold: false, calendar: calendar())), 7
        )
        XCTAssertEqual(
            day(MonthGridLayout.anchor(from: now, offset: -1, isWeekFold: true, calendar: calendar())), 8
        )
    }

    func testZeroOffsetIsToday() {
        let now = date(2026, 8, 15)
        for fold in [true, false] {
            XCTAssertEqual(
                MonthGridLayout.anchor(from: now, offset: 0, isWeekFold: fold, calendar: calendar()),
                now
            )
        }
    }

    // MARK: - Rows

    func testWeekFoldReturnsExactlyOneRowOfSeven() {
        let rows = MonthGridLayout.rows(
            anchoredOn: date(2026, 8, 15), isWeekFold: true, calendar: calendar(), now: date(2026, 8, 15)
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.count, 7)
    }

    func testMonthFoldReturnsFiveOrSixRowsOfSeven() {
        let rows = MonthGridLayout.rows(
            anchoredOn: date(2026, 8, 15), isWeekFold: false, calendar: calendar(), now: date(2026, 8, 15)
        )
        XCTAssertTrue((5 ... 6).contains(rows.count), "got \(rows.count) rows")
        XCTAssertTrue(rows.allSatisfy { $0.count == 7 })
    }

    func testFoldedWeekContainsTheAnchorDay() {
        let anchor = date(2026, 8, 15)
        let rows = MonthGridLayout.rows(
            anchoredOn: anchor, isWeekFold: true, calendar: calendar(), now: anchor
        )
        let days = rows.flatMap { $0 }.map { day($0.date) }
        XCTAssertTrue(days.contains(15), "week \(days) should contain the anchor")
    }

    func testTodayIsFlaggedInBothFolds() {
        let now = date(2026, 8, 15)
        for fold in [true, false] {
            let rows = MonthGridLayout.rows(
                anchoredOn: now, isWeekFold: fold, calendar: calendar(), now: now
            )
            XCTAssertEqual(rows.flatMap { $0 }.filter(\.isToday).count, 1, "fold=\(fold)")
        }
    }

    // MARK: - Visible range

    func testMonthRangeCoversTheWholeMonth() {
        let range = MonthGridLayout.visibleRange(
            anchoredOn: date(2026, 8, 15), isWeekFold: false, calendar: calendar()
        )
        XCTAssertEqual(day(range.start), 1)
        XCTAssertEqual(day(range.end), 31)
    }

    func testFebruaryRangeEndsOnItsRealLastDay() {
        let range = MonthGridLayout.visibleRange(
            anchoredOn: date(2027, 2, 10), isWeekFold: false, calendar: calendar()
        )
        XCTAssertEqual(day(range.end), 28, "2027 is not a leap year")
    }

    func testWeekRangeIsSevenDaysAndCanStraddleTwoMonths() {
        // The reason a folded title cannot just say "August 2026".
        let range = MonthGridLayout.visibleRange(
            anchoredOn: date(2026, 9, 1), isWeekFold: true, calendar: calendar()
        )
        let span = calendar().dateComponents([.day], from: range.start, to: range.end).day
        XCTAssertEqual(span, 6, "start and end inclusive is seven days")
        XCTAssertNotEqual(month(range.start), month(range.end), "this week straddles Aug/Sep")
    }

    func testWeekRangeRespectsFirstWeekday() {
        // firstWeekday 2 = Monday. The row must start on Monday, or the header
        // labels and the cells disagree.
        let mondayFirst = calendar(firstWeekday: 2)
        let range = MonthGridLayout.visibleRange(
            anchoredOn: date(2026, 8, 15), isWeekFold: true, calendar: mondayFirst
        )
        XCTAssertEqual(mondayFirst.component(.weekday, from: range.start), 2)
    }
}
