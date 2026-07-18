//
//  EventSearchTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for the ranked event search (MeetingBarNG).
//

import XCTest

@testable import MeetingBarLogic

final class EventSearchTests: XCTestCase {
    private func event(
        _ index: Int,
        title: String,
        notes: String? = nil,
        location: String? = nil,
        attendees: [String] = []
    ) -> SearchableEvent {
        SearchableEvent(
            sourceIndex: index,
            id: "e\(index)",
            title: title,
            notes: notes,
            location: location,
            attendees: attendees
        )
    }

    // MARK: - empty query

    func testEmptyQueryReturnsAllInInputOrderScoreZero() {
        let events = [event(0, title: "Alpha"), event(1, title: "Beta")]
        let result = EventSearch.rank(events, query: "")
        XCTAssertEqual(result.map(\.sourceIndex), [0, 1])
        XCTAssertTrue(result.allSatisfy { $0.score == 0 })
    }

    func testWhitespaceQueryReturnsAll() {
        let events = [event(0, title: "Alpha"), event(1, title: "Beta")]
        XCTAssertEqual(EventSearch.rank(events, query: "   ").count, 2)
    }

    // MARK: - match tiers / ordering

    func testExactBeatsPrefixBeatsSubstring() {
        let events = [
            event(0, title: "resync"),   // substring
            event(1, title: "sync up"),  // field prefix
            event(2, title: "sync")      // exact
        ]
        let result = EventSearch.rank(events, query: "sync")
        XCTAssertEqual(result.map(\.sourceIndex), [2, 1, 0])
    }

    func testTitleOutranksNotesForSameTerm() {
        let events = [
            event(0, title: "Standup", notes: "discuss budget"),
            event(1, title: "Budget review")
        ]
        let result = EventSearch.rank(events, query: "budget")
        XCTAssertEqual(result.first?.sourceIndex, 1)
    }

    // MARK: - normalization

    func testDiacriticInsensitive() {
        let result = EventSearch.rank([event(0, title: "Café sync")], query: "cafe")
        XCTAssertEqual(result.count, 1)
    }

    func testCaseInsensitive() {
        let result = EventSearch.rank([event(0, title: "WEEKLY Sync")], query: "weekly")
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - multi-term AND

    func testMultiTermRequiresAllTerms() {
        let events = [
            event(0, title: "Weekly Team Sync"),
            event(1, title: "Team lunch")
        ]
        let result = EventSearch.rank(events, query: "team sync")
        XCTAssertEqual(result.map(\.sourceIndex), [0])
    }

    // MARK: - people / location / notes fields

    func testAttendeeNameAndEmailHits() {
        let events = [event(0, title: "1:1", attendees: ["Dana Scully", "dana@example.com"])]
        XCTAssertEqual(EventSearch.rank(events, query: "dana").count, 1)
        XCTAssertEqual(EventSearch.rank(events, query: "scully").count, 1)
    }

    func testLocationHit() {
        let events = [event(0, title: "Sync", location: "Zoom Room 4")]
        XCTAssertEqual(EventSearch.rank(events, query: "zoom").count, 1)
    }

    func testNotesHit() {
        let events = [event(0, title: "Sync", notes: "bring the quarterly roadmap")]
        XCTAssertEqual(EventSearch.rank(events, query: "roadmap").count, 1)
    }

    // MARK: - robustness

    func testNilFieldsDoNotCrashAndNonMatchesDrop() {
        let events = [event(0, title: "Sync", notes: nil, location: nil, attendees: [])]
        XCTAssertEqual(EventSearch.rank(events, query: "sync").count, 1)
        XCTAssertTrue(EventSearch.rank(events, query: "budget").isEmpty)
    }

    func testSourceIndexTiebreakPreservesInputOrder() {
        let events = [event(5, title: "Sync"), event(2, title: "Sync")]
        let result = EventSearch.rank(events, query: "sync")
        XCTAssertEqual(result.map(\.sourceIndex), [2, 5])
    }

    func testResultSourceIndexMapsBackToEvent() {
        let events = [
            event(0, title: "Alpha"),
            event(1, title: "Beta sync"),
            event(2, title: "Gamma")
        ]
        let result = EventSearch.rank(events, query: "beta")
        XCTAssertEqual(result.count, 1)
        let hit = try? XCTUnwrap(result.first)
        XCTAssertEqual(hit?.sourceIndex, 1)
        XCTAssertEqual(events[hit!.sourceIndex].title, "Beta sync")
    }

    // MARK: - weights

    func testCustomWeightsCanPromoteNotesOverTitle() {
        // A notes-heavy weighting flips the default title-first ranking.
        let events = [
            event(0, title: "Budget", notes: "misc"),
            event(1, title: "Standup", notes: "budget")
        ]
        let weights = SearchFieldWeights(title: 0.1, attendees: 0.7, location: 0.6, notes: 1.0)
        let result = EventSearch.rank(events, query: "budget", weights: weights)
        XCTAssertEqual(result.first?.sourceIndex, 1)
    }
}
