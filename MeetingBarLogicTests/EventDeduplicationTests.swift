//
//  EventDeduplicationTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for cross-calendar duplicate collapsing (MeetingBarNG).
//

import XCTest

@testable import MeetingBarLogic

final class EventDeduplicationTests: XCTestCase {
    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: hour, minute: minute))!
    }

    private func event(
        _ sourceIndex: Int,
        externalIdentifier: String? = nil,
        title: String = "Lunch",
        start: Date,
        end: Date,
        isAllDay: Bool = false
    ) -> DeduplicationEvent {
        DeduplicationEvent(
            sourceIndex: sourceIndex,
            externalIdentifier: externalIdentifier,
            title: title,
            startDate: start,
            endDate: end,
            isAllDay: isAllDay
        )
    }

    // MARK: - External identifier

    func test_sameExternalIdentifierCollapsesToFirst() {
        let events = [
            event(0, externalIdentifier: "shared-abc", title: "Peter: Lunch", start: date(12), end: date(13)),
            // Different calendar copy: different title/time even, but same shared id.
            event(1, externalIdentifier: "shared-abc", title: "Lunch", start: date(9), end: date(10))
        ]
        XCTAssertEqual(EventDeduplication.keptIndices(events), [0])
    }

    func test_differentExternalIdentifiersAreKept() {
        let events = [
            event(0, externalIdentifier: "id-1", start: date(12), end: date(13)),
            event(1, externalIdentifier: "id-2", start: date(12), end: date(13))
        ]
        XCTAssertEqual(EventDeduplication.keptIndices(events), [0, 1])
    }

    // MARK: - Composite fallback (nil / empty external id)

    func test_nilExternalIdentifierSameTitleStartEndCollapses() {
        let events = [
            event(0, externalIdentifier: nil, title: "Lunch", start: date(12), end: date(13)),
            event(1, externalIdentifier: nil, title: "Lunch", start: date(12), end: date(13))
        ]
        XCTAssertEqual(EventDeduplication.keptIndices(events), [0])
    }

    func test_emptyExternalIdentifierFallsBackToComposite() {
        // Empty string must NOT be treated as a shared id; these two share the
        // same title/time window, so they collapse via the composite key.
        let events = [
            event(0, externalIdentifier: "", title: "Lunch", start: date(12), end: date(13)),
            event(1, externalIdentifier: "", title: "Lunch", start: date(12), end: date(13))
        ]
        XCTAssertEqual(EventDeduplication.keptIndices(events), [0])
    }

    func test_differentTimesAreKept() {
        let events = [
            event(0, title: "Lunch", start: date(12), end: date(13)),
            event(1, title: "Lunch", start: date(13), end: date(14))
        ]
        XCTAssertEqual(EventDeduplication.keptIndices(events), [0, 1])
    }

    func test_differentTitlesAreKept() {
        let events = [
            event(0, title: "Lunch", start: date(12), end: date(13)),
            event(1, title: "Dinner", start: date(12), end: date(13))
        ]
        XCTAssertEqual(EventDeduplication.keptIndices(events), [0, 1])
    }

    func test_allDayDiffersFromTimedWithSameWindow() {
        let events = [
            event(0, title: "Lunch", start: date(0), end: date(0), isAllDay: true),
            event(1, title: "Lunch", start: date(0), end: date(0), isAllDay: false)
        ]
        XCTAssertEqual(EventDeduplication.keptIndices(events), [0, 1])
    }

    // MARK: - Case / diacritic insensitivity

    func test_compositeIsCaseAndDiacriticInsensitive() {
        let events = [
            event(0, title: "Café Sync", start: date(12), end: date(13)),
            event(1, title: "cafe sync", start: date(12), end: date(13))
        ]
        XCTAssertEqual(EventDeduplication.keptIndices(events), [0])
    }

    // MARK: - Order + first-wins

    func test_orderPreservedAndFirstWins() {
        let events = [
            event(3, title: "A", start: date(9), end: date(10)),
            event(7, externalIdentifier: "dup", title: "B", start: date(11), end: date(12)),
            event(4, title: "A", start: date(9), end: date(10)),          // dup of index-0 (composite)
            event(9, externalIdentifier: "dup", title: "B2", start: date(15), end: date(16)), // dup of index-1 (ext id)
            event(2, title: "C", start: date(13), end: date(14))
        ]
        // Keeps first A (3), first "dup" (7), then C (2); the two later dups drop.
        XCTAssertEqual(EventDeduplication.keptIndices(events), [3, 7, 2])
    }

    func test_emptyInputReturnsEmpty() {
        XCTAssertEqual(EventDeduplication.keptIndices([]), [])
    }

    // MARK: - Copies that disagree about details the user cannot see
    //
    // Each of these produced two rows that rendered identically in the dropdown —
    // same title, same displayed start — because the row shows the start time
    // only unless `showEventEndTime` is on, and it is off by default. A key
    // stricter than what the user can actually see reads as a plain bug.

    func test_sameTitleAndStartCollapsesEvenWhenDurationsDiffer() {
        // A 30-minute lunch on one calendar and a 60-minute one on another.
        let events = [
            event(0, title: "Peter: Lunch", start: date(12), end: date(12, 30)),
            event(1, title: "Peter: Lunch", start: date(12), end: date(13))
        ]
        XCTAssertEqual(EventDeduplication.keptIndices(events), [0])
    }

    func test_subMinuteStartDriftCollapses() {
        // Both render "12:00"; a few seconds apart after a provider round-trip.
        let events = [
            event(0, title: "Peter: Lunch", start: date(12), end: date(13)),
            event(
                1,
                title: "Peter: Lunch",
                start: date(12).addingTimeInterval(37),
                end: date(13).addingTimeInterval(37)
            )
        ]
        XCTAssertEqual(EventDeduplication.keptIndices(events), [0])
    }

    func test_titleWhitespaceDifferencesCollapse() {
        // Trailing space, non-breaking space (U+00A0), and a doubled interior gap.
        let events = [
            event(0, title: "Peter: Lunch", start: date(12), end: date(13)),
            event(1, title: "Peter: Lunch ", start: date(12), end: date(13)),
            event(2, title: "Peter:\u{00A0}Lunch", start: date(12), end: date(13)),
            event(3, title: "Peter:  Lunch", start: date(12), end: date(13))
        ]
        XCTAssertEqual(EventDeduplication.keptIndices(events), [0])
    }

    // MARK: - Still distinct

    func test_differentStartMinutesAreStillKept() {
        // Tolerance is sub-minute only — a real back-to-back pair must survive.
        let events = [
            event(0, title: "Peter: Lunch", start: date(12), end: date(13)),
            event(1, title: "Peter: Lunch", start: date(12, 30), end: date(13))
        ]
        XCTAssertEqual(EventDeduplication.keptIndices(events), [0, 1])
    }

    func test_startsStraddlingAMinuteBoundaryAreKept() {
        // 11:59:59 and 12:00:00 display as different minutes, so they stay apart.
        // Truncation makes the boundary exactly where the user sees it.
        let events = [
            event(0, title: "Peter: Lunch", start: date(12).addingTimeInterval(-1), end: date(13)),
            event(1, title: "Peter: Lunch", start: date(12), end: date(13))
        ]
        XCTAssertEqual(EventDeduplication.keptIndices(events), [0, 1])
    }

    func test_googleShapedEventsAlwaysUseTheCompositePath() {
        // Only EventKit populates `externalIdentifier`, so every Google-sourced
        // event arrives with nil and depends entirely on the composite key.
        let events = [
            event(0, externalIdentifier: nil, title: "Peter: Lunch", start: date(12), end: date(12, 30)),
            event(1, externalIdentifier: nil, title: "peter: lunch ", start: date(12), end: date(13))
        ]
        XCTAssertEqual(EventDeduplication.keptIndices(events), [0])
    }
}
