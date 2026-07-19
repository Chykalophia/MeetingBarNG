//
//  ReminderSelectionTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for reminder due-today selection + snooze (MeetingBarNG).
//

import XCTest

@testable import MeetingBarLogic

final class ReminderSelectionTests: XCTestCase {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 15) -> Date {
        calendar().date(from: DateComponents(year: 2026, month: 7, day: day, hour: hour, minute: minute))!
    }

    private func reminder(
        _ index: Int,
        due: Date?,
        hasTime: Bool = true,
        priority: Int = 0,
        completed: Bool = false
    ) -> ReminderSelectionItem {
        ReminderSelectionItem(
            sourceIndex: index,
            id: "r\(index)",
            dueDate: due,
            hasTime: hasTime,
            priority: priority,
            isCompleted: completed
        )
    }

    // MARK: - dueToday filtering

    func testExcludesCompletedAndUndated() {
        let now = date(9)
        let items = [
            reminder(0, due: date(10)),
            reminder(1, due: date(11), completed: true),
            reminder(2, due: nil)
        ]
        let result = ReminderSelection.dueToday(from: items, now: now, calendar: calendar(), includeOverdue: true)
        XCTAssertEqual(result.map(\.sourceIndex), [0])
    }

    func testExcludesFutureDays() {
        let now = date(9)
        let items = [reminder(0, due: date(10)), reminder(1, due: date(10, day: 16))]
        let result = ReminderSelection.dueToday(from: items, now: now, calendar: calendar(), includeOverdue: true)
        XCTAssertEqual(result.map(\.sourceIndex), [0])
    }

    func testOverdueIncludedOnlyWhenRequested() {
        let now = date(12)
        let items = [reminder(0, due: date(9)), reminder(1, due: date(14))] // r0 is earlier today, r1 later today
        let overdue = reminder(2, due: date(10, day: 14)) // yesterday
        let withOverdue = ReminderSelection.dueToday(
            from: items + [overdue], now: now, calendar: calendar(), includeOverdue: true
        )
        XCTAssertEqual(Set(withOverdue.map(\.sourceIndex)), [0, 1, 2])

        let withoutOverdue = ReminderSelection.dueToday(
            from: items + [overdue], now: now, calendar: calendar(), includeOverdue: false
        )
        XCTAssertEqual(Set(withoutOverdue.map(\.sourceIndex)), [0, 1])
    }

    // MARK: - sort order

    func testSortsOverdueFirstThenDueThenPriorityThenIndex() {
        let now = date(12)
        let items = [
            reminder(0, due: date(16)),                 // later today
            reminder(1, due: date(10, day: 14)),        // overdue (yesterday)
            reminder(2, due: date(14)),                 // today, earlier than r0
            reminder(3, due: date(14), priority: 1)     // same due as r2, higher priority
        ]
        let result = ReminderSelection.dueToday(
            from: items, now: now, calendar: calendar(), includeOverdue: true
        )
        // overdue r1, then r3 (same time as r2 but higher priority), then r2, then r0.
        XCTAssertEqual(result.map(\.sourceIndex), [1, 3, 2, 0])
    }

    func testPriorityNoneSortsLast() {
        let now = date(9)
        let items = [
            reminder(0, due: date(12), priority: 0), // none
            reminder(1, due: date(12), priority: 5), // medium
            reminder(2, due: date(12), priority: 1)  // high
        ]
        let result = ReminderSelection.dueToday(
            from: items, now: now, calendar: calendar(), includeOverdue: true
        )
        XCTAssertEqual(result.map(\.sourceIndex), [2, 1, 0])
    }

    // MARK: - snooze

    func testSnoozeLaterTodayAddsOneHour() {
        let now = date(9, 30)
        let due = ReminderSnoozePolicy.newDueDate(from: now, option: .laterToday, calendar: calendar())
        XCTAssertEqual(due, now.addingTimeInterval(3600))
    }

    func testSnoozeThisEveningUsesEveningHour() {
        let now = date(9)
        let due = ReminderSnoozePolicy.newDueDate(
            from: now, option: .thisEvening, calendar: calendar(), eveningHour: 18
        )
        XCTAssertEqual(due, date(18))
    }

    func testSnoozeThisEveningFallsBackWhenPast() {
        let now = date(20) // already past 18:00
        let due = ReminderSnoozePolicy.newDueDate(
            from: now, option: .thisEvening, calendar: calendar(), eveningHour: 18
        )
        XCTAssertEqual(due, now.addingTimeInterval(3600))
    }

    func testSnoozeTomorrowUsesMorningHourNextDay() {
        let now = date(22)
        let due = ReminderSnoozePolicy.newDueDate(
            from: now, option: .tomorrow, calendar: calendar(), morningHour: 9
        )
        XCTAssertEqual(due, date(9, day: 16))
    }
}
