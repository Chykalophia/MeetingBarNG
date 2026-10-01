//
//  MultiSourceDeduplicationTests.swift
//  MeetingBarNGTests
//
//  With macOS Calendar and the direct Google provider connected at the same
//  time, the same invite arrives twice. `EventDeduplication` collapses it, and
//  `sourcePriority` decides which copy survives — these tests drive that through
//  the real fetch pipeline rather than the pure deduplicator, because the wiring
//  between them (calendar `provider`, per-source selection, the priority
//  lookup) is where it can silently go wrong.
//

import Combine
import Defaults
import XCTest

@testable import Punctual

@MainActor
final class MultiSourceDeduplicationTests: BaseTestCase {
    private var cancellables = Set<AnyCancellable>()

    private struct Harness {
        let sync: CalendarSync
        let eventKitCalendar: MBCalendar
        let googleCalendar: MBCalendar
    }

    private func makeHarness(
        googleTitle: String,
        eventKitTitle: String,
        start: Date
    ) -> Harness {
        let eventKitCalendar = makeFakeCalendar(id: "ek-cal", title: "EventKit Cal")
        let googleCalendar = makeFakeCalendar(
            id: "g-cal", title: "Google Cal", provider: .googleCalendar)

        Defaults[.deduplicateEvents] = true
        Defaults[.eventStoreProvider] = .macOSEventKit
        Defaults[.selectedCalendarIDsByProvider] = [
            EventStoreProvider.macOSEventKit.rawValue: [eventKitCalendar.id],
            EventStoreProvider.googleCalendar.rawValue: [googleCalendar.id]
        ]
        Defaults[.selectedCalendarIDsByProviderMigrated] = true
        Defaults[.enabledCalendarSources] = [.macOSEventKit, .googleCalendar]
        Defaults[.enabledCalendarSourcesMigrated] = true

        let eventKitStore = FakeEventStore(
            calendars: [eventKitCalendar],
            events: [
                makeFakeEvent(
                    id: "ek-copy",
                    start: start,
                    end: start.addingTimeInterval(1800),
                    title: eventKitTitle,
                    calendar: eventKitCalendar
                )
            ]
        )
        let googleStore = FakeEventStore(
            calendars: [googleCalendar],
            events: [
                makeFakeEvent(
                    id: "g-copy",
                    start: start,
                    end: start.addingTimeInterval(3600),
                    title: googleTitle,
                    calendar: googleCalendar
                )
            ]
        )
        let repository = CalendarRepository(
            selection: CalendarSourceSelection(providers: [.macOSEventKit, .googleCalendar])
        ) { provider in
            provider == .macOSEventKit ? eventKitStore : googleStore
        }
        return Harness(
            sync: CalendarSync(repository: repository, refreshInterval: 0),
            eventKitCalendar: eventKitCalendar,
            googleCalendar: googleCalendar
        )
    }

    private func waitForEvents(_ sync: CalendarSync) async {
        let exp = expectation(description: "events published")
        sync.$providerHealth
            .drop(while: { $0.lastSuccessfulRefresh == nil })
            .first()
            .sink { _ in exp.fulfill() }
            .store(in: &cancellables)
        await fulfillment(of: [exp], timeout: 2.0)
    }

    /// The headline behaviour: one row, and it is Google's copy.
    func testTheGoogleCopyOfADuplicatedMeetingSurvives() async {
        let start = Date().addingTimeInterval(600)
        let harness = makeHarness(
            googleTitle: "Standup", eventKitTitle: "Standup", start: start)

        await waitForEvents(harness.sync)

        XCTAssertEqual(harness.sync.events.count, 1, "the duplicate must collapse to one row")
        XCTAssertEqual(harness.sync.events.first?.id, "g-copy")
        XCTAssertEqual(
            harness.sync.events.first?.calendar.provider,
            .googleCalendar,
            "the surviving copy carries Google's richer payload")
    }

    /// Copies that disagree about duration still collapse — a 30-minute block on
    /// one source and 60 on the other is one meeting, and the row shows only the
    /// start time by default.
    func testCopiesWithDifferentEndTimesStillCollapse() async {
        let start = Date().addingTimeInterval(600)
        let harness = makeHarness(
            googleTitle: "Standup ", eventKitTitle: "standup", start: start)

        await waitForEvents(harness.sync)

        XCTAssertEqual(harness.sync.events.count, 1)
        XCTAssertEqual(harness.sync.events.first?.id, "g-copy")
    }

    /// Genuinely different meetings from the two sources both survive.
    func testDistinctMeetingsFromBothSourcesAreBothKept() async {
        let start = Date().addingTimeInterval(600)
        let harness = makeHarness(
            googleTitle: "Design review", eventKitTitle: "1:1 with Sam", start: start)

        await waitForEvents(harness.sync)

        XCTAssertEqual(
            Set(harness.sync.events.map(\.id)),
            ["ek-copy", "g-copy"],
            "deduplication must not merge two different meetings that merely overlap")
    }

    /// The opt-out still applies across sources.
    func testTurningDeduplicationOffShowsBothCopies() async {
        let start = Date().addingTimeInterval(600)
        let harness = makeHarness(
            googleTitle: "Standup", eventKitTitle: "Standup", start: start)
        Defaults[.deduplicateEvents] = false

        await waitForEvents(harness.sync)
        // The setting is a refresh trigger, so the first published set may
        // predate it; force one more cycle.
        try? await harness.sync.refreshSources()
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(Set(harness.sync.events.map(\.id)), ["ek-copy", "g-copy"])
    }

    /// Both sources' calendars reach the merged list, each filtered against its
    /// OWN selection. Filtering the merged list against one provider's ID list
    /// would silently drop the other source entirely.
    func testEachSourceIsFilteredAgainstItsOwnSelection() async {
        let start = Date().addingTimeInterval(600)
        let harness = makeHarness(
            googleTitle: "Design review", eventKitTitle: "1:1 with Sam", start: start)

        await waitForEvents(harness.sync)

        XCTAssertEqual(
            Set(harness.sync.calendars.map(\.id)),
            [harness.eventKitCalendar.id, harness.googleCalendar.id]
        )
    }
}
