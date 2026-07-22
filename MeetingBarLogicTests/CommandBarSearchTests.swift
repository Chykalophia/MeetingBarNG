//
//  CommandBarSearchTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for Command Bar ranking + agenda assembly (MeetingBarNG).
//

import XCTest

@testable import MeetingBarLogic

final class CommandBarSearchTests: XCTestCase {
    // 2026-05-09 06:13:20 UTC.
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func event(
        _ index: Int,
        title: String,
        subtitle: String = "",
        startOffset: TimeInterval,
        endOffset: TimeInterval,
        isAllDay: Bool = false,
        hasMeetingLink: Bool = false,
        location: String? = nil,
        notes: String? = nil,
        attendees: [String] = []
    ) -> CommandBarEventInput {
        CommandBarEventInput(
            sourceIndex: index,
            id: "e\(index)",
            title: title,
            subtitle: subtitle,
            startDate: now.addingTimeInterval(startOffset),
            endDate: now.addingTimeInterval(endOffset),
            isAllDay: isAllDay,
            hasMeetingLink: hasMeetingLink,
            location: location,
            notes: notes,
            attendees: attendees
        )
    }

    private func action(
        _ action: CommandBarAction,
        title: String,
        searchable: [String] = [],
        priority: Bool = false,
        subtitle: String? = nil
    ) -> CommandBarActionDescriptor {
        CommandBarActionDescriptor(
            action: action,
            title: title,
            subtitle: subtitle,
            searchableText: searchable,
            isPriority: priority
        )
    }

    // MARK: - default (empty-query) order

    func testEmptyQueryOrdersPriorityActionsThenUpcomingThenRest() {
        let actions = [
            action(.joinNext, title: "Join next meeting", priority: true),
            action(.createMeeting, title: "Create meeting", priority: true),
            action(.openPreferences, title: "Open Preferences", priority: false)
        ]
        let events = [
            event(0, title: "Ended", startOffset: -3600, endOffset: -1800),
            event(1, title: "Soon", startOffset: 600, endOffset: 1800),
            event(2, title: "Later", startOffset: 3600, endOffset: 5400)
        ]
        let rows = CommandBarSearch.results(
            query: "", events: events, actions: actions, now: now, calendar: calendar()
        )
        XCTAssertEqual(
            rows.map(\.title),
            ["Join next meeting", "Create meeting", "Soon", "Later", "Open Preferences"]
        )
    }

    // MARK: - action matching

    func testActionMatchedBySynonym() {
        let actions = [action(.joinNext, title: "Join next meeting", searchable: ["join", "next"])]
        let rows = CommandBarSearch.results(
            query: "join", events: [], actions: actions, now: now, calendar: calendar()
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.result, .action(.joinNext))
    }

    func testNonMatchingActionExcluded() {
        let actions = [action(.openPreferences, title: "Open Preferences", searchable: ["settings"])]
        let rows = CommandBarSearch.results(
            query: "zzz", events: [], actions: actions, now: now, calendar: calendar()
        )
        XCTAssertTrue(rows.isEmpty)
    }

    func testMultiTermActionRequiresAllTerms() {
        let actions = [action(.joinNext, title: "Join next meeting", searchable: ["join", "next"])]
        XCTAssertEqual(
            CommandBarSearch.results(
                query: "join next", events: [], actions: actions, now: now, calendar: calendar()
            ).count,
            1
        )
        XCTAssertTrue(
            CommandBarSearch.results(
                query: "join zzz", events: [], actions: actions, now: now, calendar: calendar()
            ).isEmpty
        )
    }

    func testStableTiebreakPreservesActionInputOrder() {
        let actions = [
            action(.joinNext, title: "Alpha", searchable: ["match"]),
            action(.createMeeting, title: "Beta", searchable: ["match"])
        ]
        let rows = CommandBarSearch.results(
            query: "match", events: [], actions: actions, now: now, calendar: calendar()
        )
        XCTAssertEqual(rows.map(\.result), [.action(.joinNext), .action(.createMeeting)])
    }

    // MARK: - event matching + interleaving

    func testEventMatchedByTitle() {
        let events = [event(0, title: "Design review", startOffset: 600, endOffset: 1800)]
        let rows = CommandBarSearch.results(
            query: "design", events: events, actions: [], now: now, calendar: calendar()
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.result, .event("e0"))
    }

    func testActionsAndEventsInterleaveByScore() {
        // Exact action-synonym match (tier 4) outranks an event word-boundary
        // match (tier 2), so the action sorts first while both appear.
        let actions = [action(.createMeeting, title: "Create meeting", searchable: ["meeting"])]
        let events = [event(0, title: "Team meeting", startOffset: 600, endOffset: 1800)]
        let rows = CommandBarSearch.results(
            query: "meeting", events: events, actions: actions, now: now, calendar: calendar()
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first?.result, .action(.createMeeting))
        XCTAssertEqual(rows.last?.result, .event("e0"))
    }

    // MARK: - agenda assembly

    func testAgendaTextAssembly() {
        let entries = [
            CommandBarAgendaEntry(title: "Standup", timeRange: "9:00 – 9:15", isAllDay: false),
            CommandBarAgendaEntry(title: "Holiday", timeRange: "", isAllDay: true)
        ]
        let text = CommandBarAgenda.text(for: entries, header: "Today", emptyPlaceholder: "Nothing")
        XCTAssertEqual(text, "Today\n• 9:00 – 9:15  Standup\n• Holiday")
    }

    func testAgendaEmptyUsesPlaceholder() {
        XCTAssertEqual(
            CommandBarAgenda.text(for: [], header: "Today", emptyPlaceholder: "Nothing scheduled"),
            "Today\nNothing scheduled"
        )
    }
}
