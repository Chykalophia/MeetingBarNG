//
//  DropdownPanelNavigationTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for the SwiftUI dropdown panel's keyboard-navigation model
//  (MeetingBarNG, Phase B): the flattened list of interactive rows and the
//  clamped selection math. Keeps the panel's keyboard behavior verifiable
//  without a UI test.
//

import XCTest

@testable import MeetingBarLogic

final class DropdownPanelNavigationTests: XCTestCase {
    // MARK: - interactiveRows

    func testGreetingAndTimelineContributeNoRows() {
        let rows = DropdownPanelNavigation.interactiveRows(
            for: DropdownPanelContent(modules: [.greeting, .timeline])
        )
        // Only the pinned footer remains.
        XCTAssertEqual(rows, [.preferences, .quit])
    }

    func testMeetingModuleYieldsSummaryRowWhenAnEventIsShown() {
        let rows = DropdownPanelNavigation.interactiveRows(
            for: DropdownPanelContent(modules: [.meeting], meetingEventID: "evt-1")
        )
        XCTAssertEqual(rows, [.meetingSummary("evt-1"), .preferences, .quit])
    }

    func testMeetingModuleYieldsEmptyStateActionWithoutAnEvent() {
        let rows = DropdownPanelNavigation.interactiveRows(
            for: DropdownPanelContent(modules: [.meeting])
        )
        XCTAssertEqual(rows, [.emptyStateAction, .preferences, .quit])
    }

    func testAgendaOrdersTodayThenRemindersThenTomorrow() {
        let rows = DropdownPanelNavigation.interactiveRows(
            for: DropdownPanelContent(
                modules: [.agenda],
                todayEventIDs: ["a", "b"],
                reminderIDs: ["r1"],
                tomorrowEventIDs: ["c"]
            )
        )
        XCTAssertEqual(
            rows,
            [.event("a"), .event("b"), .reminder("r1"), .event("c"), .preferences, .quit]
        )
    }

    // MARK: - Row cap overflow
    //
    // The panel caps each agenda section and offers a "+N more" row. Navigation
    // must walk onto that row (it is the only way to reach the withheld events
    // with the keyboard) and must NOT walk onto the events still hidden behind
    // it — `todayEventIDs`/`tomorrowEventIDs` arrive already capped.

    func testOverflowRowFollowsTheEventsItUnfolds() {
        let rows = DropdownPanelNavigation.interactiveRows(
            for: DropdownPanelContent(
                modules: [.agenda],
                todayEventIDs: ["a", "b"],
                todayHasHiddenEvents: true
            )
        )
        XCTAssertEqual(
            rows,
            [.event("a"), .event("b"), .showMoreEvents(.today), .preferences, .quit]
        )
    }

    func testOverflowRowIsAbsentWhenNothingIsWithheld() {
        let rows = DropdownPanelNavigation.interactiveRows(
            for: DropdownPanelContent(modules: [.agenda], todayEventIDs: ["a", "b"])
        )
        XCTAssertEqual(rows, [.event("a"), .event("b"), .preferences, .quit])
    }

    func testEachDayGetsItsOwnOverflowRowInVisualOrder() {
        let rows = DropdownPanelNavigation.interactiveRows(
            for: DropdownPanelContent(
                modules: [.agenda],
                todayEventIDs: ["a"],
                reminderIDs: ["r1"],
                tomorrowEventIDs: ["t1"],
                todayHasHiddenEvents: true,
                tomorrowHasHiddenEvents: true
            )
        )
        // Today's overflow sits above the reminders, tomorrow's below its events.
        XCTAssertEqual(
            rows,
            [
                .event("a"), .showMoreEvents(.today),
                .reminder("r1"),
                .event("t1"), .showMoreEvents(.tomorrow),
                .preferences, .quit
            ]
        )
    }

    func testTomorrowOverflowIsIndependentOfToday() {
        let rows = DropdownPanelNavigation.interactiveRows(
            for: DropdownPanelContent(
                modules: [.agenda],
                todayEventIDs: ["a"],
                tomorrowEventIDs: ["t1"],
                tomorrowHasHiddenEvents: true
            )
        )
        XCTAssertEqual(
            rows,
            [.event("a"), .event("t1"), .showMoreEvents(.tomorrow), .preferences, .quit]
        )
    }

    func testJoinModuleYieldsJoinThenCreate() {
        let rows = DropdownPanelNavigation.interactiveRows(
            for: DropdownPanelContent(modules: [.join], joinNextEventID: "evt-9")
        )
        XCTAssertEqual(rows, [.joinNext("evt-9"), .createMeeting, .preferences, .quit])
    }

    func testJoinModuleWithoutANextMeetingStillOffersCreate() {
        let rows = DropdownPanelNavigation.interactiveRows(
            for: DropdownPanelContent(modules: [.join])
        )
        XCTAssertEqual(rows, [.createMeeting, .preferences, .quit])
    }

    func testBookmarksYieldOneRowPerBookmark() {
        let rows = DropdownPanelNavigation.interactiveRows(
            for: DropdownPanelContent(modules: [.bookmarks], bookmarkCount: 3)
        )
        XCTAssertEqual(
            rows,
            [.bookmark(0), .bookmark(1), .bookmark(2), .preferences, .quit]
        )
    }

    func testFooterAddsWhatsNewWhenUnread() {
        let rows = DropdownPanelNavigation.interactiveRows(
            for: DropdownPanelContent(modules: [], showsWhatsNew: true)
        )
        XCTAssertEqual(rows, [.whatsNew, .preferences, .quit])
    }

    func testRowsFollowTheStoredModuleOrder() {
        let rows = DropdownPanelNavigation.interactiveRows(
            for: DropdownPanelContent(
                modules: [.join, .agenda, .meeting],
                meetingEventID: "evt-1",
                todayEventIDs: ["a"],
                joinNextEventID: "evt-1"
            )
        )
        XCTAssertEqual(
            rows,
            [
                .joinNext("evt-1"), .createMeeting,
                .event("a"),
                .meetingSummary("evt-1"),
                .preferences, .quit
            ]
        )
    }

    // MARK: - next(from:direction:count:)

    func testNextFromNoSelectionSelectsFirstRowGoingDown() {
        XCTAssertEqual(DropdownPanelNavigation.next(from: nil, direction: .down, count: 4), 0)
    }

    func testNextFromNoSelectionSelectsLastRowGoingUp() {
        XCTAssertEqual(DropdownPanelNavigation.next(from: nil, direction: .up, count: 4), 3)
    }

    func testNextMovesOneStepInEachDirection() {
        XCTAssertEqual(DropdownPanelNavigation.next(from: 1, direction: .down, count: 4), 2)
        XCTAssertEqual(DropdownPanelNavigation.next(from: 1, direction: .up, count: 4), 0)
    }

    func testNextClampsAtBothEnds() {
        XCTAssertEqual(DropdownPanelNavigation.next(from: 3, direction: .down, count: 4), 3)
        XCTAssertEqual(DropdownPanelNavigation.next(from: 0, direction: .up, count: 4), 0)
    }

    func testNextReturnsNilWhenThereAreNoRows() {
        XCTAssertNil(DropdownPanelNavigation.next(from: nil, direction: .down, count: 0))
        XCTAssertNil(DropdownPanelNavigation.next(from: 0, direction: .up, count: 0))
    }

    func testNextClampsAnOutOfRangeSelection() {
        // A stale index (rows shrank under the selection) snaps back in bounds
        // instead of walking further out.
        XCTAssertEqual(DropdownPanelNavigation.next(from: 99, direction: .down, count: 3), 2)
        XCTAssertEqual(DropdownPanelNavigation.next(from: 99, direction: .up, count: 3), 2)
        XCTAssertEqual(DropdownPanelNavigation.next(from: -5, direction: .up, count: 3), 0)
    }
}
