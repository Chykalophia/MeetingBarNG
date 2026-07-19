//
//  EventDraftValidationTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for in-app event create/edit draft validation (MeetingBarNG).
//

import XCTest

@testable import MeetingBarLogic

final class EventDraftValidationTests: XCTestCase {
    private func date(hour: Int, minute: Int = 0, day: Int = 17) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(
            from: DateComponents(year: 2026, month: 7, day: day, hour: hour, minute: minute)
        )!
    }

    private func draft(
        title: String = "Standup",
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        calendarID: String? = "cal-1"
    ) -> EventDraft {
        EventDraft(
            title: title,
            startDate: start,
            endDate: end,
            isAllDay: isAllDay,
            calendarID: calendarID,
            location: "",
            notes: "",
            url: ""
        )
    }

    func testValidTimedEventHasNoErrors() {
        let subject = draft(start: date(hour: 9), end: date(hour: 10))
        XCTAssertTrue(EventDraftValidation.validate(subject).isEmpty)
    }

    func testEmptyTitleIsInvalid() {
        // Whitespace-only titles count as empty.
        let subject = draft(title: "   ", start: date(hour: 9), end: date(hour: 10))
        XCTAssertEqual(EventDraftValidation.validate(subject), [.emptyTitle])
    }

    func testEndBeforeStartIsInvalidForTimedEvent() {
        let subject = draft(start: date(hour: 10), end: date(hour: 9))
        XCTAssertTrue(EventDraftValidation.validate(subject).contains(.endBeforeStart))
    }

    func testEndEqualStartIsInvalidForTimedEvent() {
        let subject = draft(start: date(hour: 9), end: date(hour: 9))
        XCTAssertTrue(EventDraftValidation.validate(subject).contains(.endBeforeStart))
    }

    func testAllDayAllowsEqualDates() {
        // An all-day event spanning a single day has equal start/end dates and is valid.
        let subject = draft(start: date(hour: 0), end: date(hour: 0), isAllDay: true)
        XCTAssertTrue(EventDraftValidation.validate(subject).isEmpty)
    }

    func testMissingCalendarIsInvalid() {
        let subject = draft(start: date(hour: 9), end: date(hour: 10), calendarID: nil)
        XCTAssertEqual(EventDraftValidation.validate(subject), [.missingCalendar])
    }

    func testEmptyCalendarIDIsInvalid() {
        let subject = draft(start: date(hour: 9), end: date(hour: 10), calendarID: "")
        XCTAssertEqual(EventDraftValidation.validate(subject), [.missingCalendar])
    }

    func testMultipleErrorsAreReported() {
        let subject = draft(title: "", start: date(hour: 10), end: date(hour: 9), calendarID: nil)
        XCTAssertEqual(
            Set(EventDraftValidation.validate(subject)),
            [.emptyTitle, .endBeforeStart, .missingCalendar]
        )
    }
}
