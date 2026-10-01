//
//  CalendarSyncTests.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//
import Combine
import Defaults
import XCTest

@testable import Punctual

@MainActor
class CalendarSyncTests: BaseTestCase {
    private var cancellables = Set<AnyCancellable>()

    func testInjectedStorePublishesCalendarsAndEvents() {
        // 1) Prepare fakes
        let fakeCal = MBCalendar(title: "Cal A", id: "calA", source: nil, email: nil, color: .black)
        let fakeEvt = makeFakeEvent(
            id: "E1",
            start: Date().addingTimeInterval(60),
            end: Date().addingTimeInterval(3600)
        )
        let fakeStore = FakeEventStore(
            calendars: [fakeCal],
            events: [fakeEvt]
        )

        // 2) Create manager with test initializer
        let manager = CalendarSync(
            provider: fakeStore,
            refreshInterval: 0.05
        )

        // 3) Observe first non-empty values of calendars & events
        let calExpectation = expectation(description: "calendars published")
        manager.$calendars
            .drop(while: \.isEmpty)
            .first()
            .sink { cals in
                XCTAssertEqual(cals, [fakeCal])
                calExpectation.fulfill()
            }
            .store(in: &cancellables)

        let evtExpectation = expectation(description: "events published")
        manager.$events
            .drop(while: \.isEmpty)
            .first()
            .sink { evts in
                XCTAssertEqual(evts, [fakeEvt])
                evtExpectation.fulfill()
            }
            .store(in: &cancellables)

        // 4) Wait
        wait(for: [calExpectation, evtExpectation], timeout: 1.0)
    }

    func testRefreshPreservesSelectedSharedGoogleCalendars() async throws {
        // Calendars declare the source they came from; a Google-backed calendar
        // that claims to be EventKit's is routed to the wrong store.
        let primary = MBCalendar(
            title: "Primary", id: "primary", source: nil, email: nil, color: .black,
            provider: .googleCalendar)
        let shared = MBCalendar(
            title: "Shared", id: "shared-public", source: nil, email: nil, color: .black,
            provider: .googleCalendar)
        Defaults[.eventStoreProvider] = .googleCalendar
        Defaults[.selectedCalendarIDs] = [primary.id, shared.id]
        Defaults[.selectedCalendarIDsByProvider] = [
            EventStoreProvider.googleCalendar.rawValue: [primary.id, shared.id]
        ]
        Defaults[.selectedCalendarIDsByProviderMigrated] = true

        let store = FakeEventStore(calendars: [primary, shared])
        let repository = CalendarRepository(providerName: .googleCalendar) { _ in store }
        let manager = CalendarSync(repository: repository, refreshInterval: 0)

        let initialExp = expectation(description: "initial Google refresh")
        manager.$providerHealth
            .drop(while: { $0.lastSuccessfulRefresh == nil })
            .first()
            .sink { _ in initialExp.fulfill() }
            .store(in: &cancellables)
        await fulfillment(of: [initialExp], timeout: 1.0)

        XCTAssertEqual(
            Set(store.fetchedEventCalendarIDs.last ?? []),
            Set([primary.id, shared.id])
        )

        try await Task.sleep(nanoseconds: 250_000_000)
        let refreshExp = expectation(description: "manual Google refresh")
        manager.$providerHealth
            .dropFirst()
            .first()
            .sink { _ in refreshExp.fulfill() }
            .store(in: &cancellables)

        try await manager.refreshSources()
        await fulfillment(of: [refreshExp], timeout: 1.0)

        XCTAssertEqual(
            AppSettings.selectedCalendarIDs(for: .googleCalendar),
            [primary.id, shared.id]
        )
        XCTAssertEqual(
            Set(store.fetchedEventCalendarIDs.last ?? []),
            Set([primary.id, shared.id])
        )
    }
}

@MainActor class CalendarSyncSwitchProviderTests: BaseTestCase {

    private var cancellables = Set<AnyCancellable>()

    func testSwitchProviderPublishesNewEvents() async throws {
        // Arrange: two fake stores with different events
        let firstEvent = makeFakeEvent(
            id: "A",
            start: Date(),
            end: Date().addingTimeInterval(3600)
        )
        let secondEvent = makeFakeEvent(
            id: "B",
            start: Date().addingTimeInterval(7200),
            end: Date().addingTimeInterval(10_800)
        )

        let storeA = FakeEventStore(events: [firstEvent])
        let storeB = FakeEventStore(events: [secondEvent])

        // Start CalendarSync with Store A
        let manager = CalendarSync(provider: storeA, refreshInterval: 0)

        // Expect the first publication to contain [firstEvent]
        let initialExp = expectation(description: "initial events")
        manager.$events
            .drop(while: \.isEmpty)
            .first()  // Failure == Never
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { events in
                    XCTAssertEqual(events, [firstEvent])
                    initialExp.fulfill()
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [initialExp], timeout: 1.0)

        // Prepare second expectation BEFORE switching the store
        let switchedExp = expectation(description: "events after switch")
        manager.$events
            .dropFirst()  // skip current value
            .first()
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { events in
                    XCTAssertEqual(events, [secondEvent])
                    switchedExp.fulfill()
                }
            )
            .store(in: &cancellables)

        // Act: replace the provider and trigger refresh
        manager.repository = CalendarRepository(store: storeB)
        try await manager.refreshSources()  // sends refreshSubject

        await fulfillment(of: [switchedExp], timeout: 1.0)

    }

    func testStoreChangeSubscriptionDoesNotStackAfterProviderSwitches() async throws {
        let calendar = MBCalendar(title: "C", id: "c1", source: nil, email: nil, color: .black)
        let eventKitStore = FakeEventStore(calendars: [calendar])
        // A store PER provider, so the count below is unambiguous: with one
        // shared fake, connecting both sources would legitimately refresh it
        // twice per notification and the assertion could not tell that apart
        // from a stacked subscription, which is what this test is about.
        let googleStore = FakeEventStore(calendars: [
            MBCalendar(
                title: "G", id: "g1", source: nil, email: nil, color: .black,
                provider: .googleCalendar)
        ])
        let repository = CalendarRepository(providerName: .macOSEventKit) { provider in
            provider == .macOSEventKit ? eventKitStore : googleStore
        }
        let manager = CalendarSync(repository: repository, refreshInterval: 0)

        let initialExp = expectation(description: "initial refresh completed")
        manager.$providerHealth
            .drop(while: { $0.lastAttemptedRefresh == nil })
            .first()
            .sink { _ in initialExp.fulfill() }
            .store(in: &cancellables)
        await fulfillment(of: [initialExp], timeout: 1.0)

        // Connecting and disconnecting re-subscribes each time; the sinks must
        // not accumulate.
        _ = await manager.changeEventStoreProvider(.googleCalendar)
        await manager.disconnectEventStoreProvider(.googleCalendar)

        let countBeforeStoreChange = eventKitStore.refreshSourcesCallCount
        manager.repository.storeChanged.send()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(
            eventKitStore.refreshSourcesCallCount - countBeforeStoreChange,
            1,
            "one store-change notification should trigger one refreshSources call")
    }

    /// Connecting a second source must NOT tear the first one down — that is the
    /// whole point of multi-source. Disconnecting cancels only the source being
    /// disconnected, and `stop()` cancels everything still connected.
    func testConnectingASecondSourceLeavesTheFirstRunning() async throws {
        let storeA = FakeEventStore(calendars: [
            MBCalendar(title: "EventKit", id: "eventkit", source: nil, email: nil, color: .black)
        ])
        let storeB = FakeEventStore(calendars: [
            MBCalendar(
                title: "Google",
                id: "google",
                source: nil,
                email: nil,
                color: .black,
                provider: .googleCalendar
            )
        ])
        let repository = CalendarRepository(providerName: .macOSEventKit) { provider in
            provider == .macOSEventKit ? storeA : storeB
        }

        _ = try await repository.connect(.googleCalendar)

        XCTAssertEqual(
            repository.selection.providers,
            [.macOSEventKit, .googleCalendar],
            "connecting adds a source rather than replacing the existing one")
        XCTAssertEqual(
            storeA.cancelPendingOperationsCallCount, 0,
            "the already-connected source must keep running")
        XCTAssertEqual(storeB.cancelPendingOperationsCallCount, 0)

        repository.stop()

        XCTAssertEqual(storeA.cancelPendingOperationsCallCount, 1)
        XCTAssertEqual(storeB.cancelPendingOperationsCallCount, 1)
    }

    func testDisconnectingCancelsOnlyThatSource() async throws {
        let storeA = FakeEventStore(calendars: [
            MBCalendar(title: "EventKit", id: "eventkit", source: nil, email: nil, color: .black)
        ])
        let storeB = FakeEventStore(calendars: [
            MBCalendar(
                title: "Google",
                id: "google",
                source: nil,
                email: nil,
                color: .black,
                provider: .googleCalendar
            )
        ])
        let repository = CalendarRepository(providerName: .macOSEventKit) { provider in
            provider == .macOSEventKit ? storeA : storeB
        }
        _ = try await repository.connect(.googleCalendar)

        await repository.disconnect(.googleCalendar)

        XCTAssertEqual(repository.selection.providers, [.macOSEventKit])
        XCTAssertEqual(storeB.cancelPendingOperationsCallCount, 1)
        XCTAssertEqual(storeA.cancelPendingOperationsCallCount, 0)
    }

    /// The last connected source cannot be disconnected — an install that
    /// reaches no source at all renders an empty dropdown that reads as broken.
    func testDisconnectingTheLastSourceIsRefused() async throws {
        let storeA = FakeEventStore(calendars: [
            MBCalendar(title: "EventKit", id: "eventkit", source: nil, email: nil, color: .black)
        ])
        let repository = CalendarRepository(providerName: .macOSEventKit) { _ in storeA }

        await repository.disconnect(.macOSEventKit)

        XCTAssertEqual(repository.selection.providers, [.macOSEventKit])
        XCTAssertEqual(storeA.cancelPendingOperationsCallCount, 0)
    }

    /// One source failing must not blank out the source that worked.
    func testAFailingSourceDoesNotHideTheWorkingOne() async throws {
        let eventKitCalendar = MBCalendar(
            title: "EventKit", id: "eventkit", source: nil, email: nil, color: .black
        )
        let storeA = FakeEventStore(calendars: [eventKitCalendar])
        let storeB = FakeEventStore(calendars: [
            MBCalendar(
                title: "Google", id: "google", source: nil, email: nil, color: .black,
                provider: .googleCalendar
            )
        ])
        let repository = CalendarRepository(providerName: .macOSEventKit) { provider in
            provider == .macOSEventKit ? storeA : storeB
        }
        _ = try await repository.connect(.googleCalendar)

        // Google's token lapses after connecting.
        storeB.stubbedCalendarError = GoogleCalendarError.unauthorized(URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!)

        let outcome = try await repository.fetchAllCalendars()

        XCTAssertEqual(outcome.elements, [eventKitCalendar])
        XCTAssertEqual(outcome.failures.map(\.provider), [.googleCalendar])
        XCTAssertTrue(outcome.failures.allSatisfy(\.authRequired))
    }

    func testCancelledSwitchPreservesProviderAndSelectedCalendars() async {
        let eventKitCalendar = MBCalendar(
            title: "EventKit",
            id: "eventkit",
            source: nil,
            email: nil,
            color: .black
        )
        Defaults[.eventStoreProvider] = .macOSEventKit
        Defaults[.selectedCalendarIDs] = [eventKitCalendar.id]
        Defaults[.selectedCalendarIDsByProvider] = [
            EventStoreProvider.macOSEventKit.rawValue: [eventKitCalendar.id],
            EventStoreProvider.googleCalendar.rawValue: ["google-previous"]
        ]
        Defaults[.selectedCalendarIDsByProviderMigrated] = true

        let eventKitStore = FakeEventStore(calendars: [eventKitCalendar])
        let googleStore = FakeEventStore()
        googleStore.stubbedSignInError = AuthError.cancelled
        let repository = CalendarRepository(providerName: .macOSEventKit) { provider in
            provider == .macOSEventKit ? eventKitStore : googleStore
        }
        let manager = CalendarSync(repository: repository, refreshInterval: 0)

        let result = await manager.changeEventStoreProvider(.googleCalendar)

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(repository.activeProviderName, .macOSEventKit)
        XCTAssertEqual(Defaults[.eventStoreProvider], .macOSEventKit)
        XCTAssertEqual(Defaults[.selectedCalendarIDs], [eventKitCalendar.id])
        XCTAssertEqual(
            AppSettings.selectedCalendarIDs(for: .macOSEventKit),
            [eventKitCalendar.id]
        )
        XCTAssertEqual(
            AppSettings.selectedCalendarIDs(for: .googleCalendar),
            ["google-previous"]
        )
        XCTAssertEqual(eventKitStore.cancelPendingOperationsCallCount, 0)
    }

    func testFailedSwitchPreservesProviderAndProviderScopedSelections() async {
        let eventKitCalendar = MBCalendar(
            title: "EventKit",
            id: "eventkit",
            source: nil,
            email: nil,
            color: .black
        )
        Defaults[.eventStoreProvider] = .macOSEventKit
        Defaults[.selectedCalendarIDs] = [eventKitCalendar.id]
        Defaults[.selectedCalendarIDsByProvider] = [
            EventStoreProvider.macOSEventKit.rawValue: [eventKitCalendar.id],
            EventStoreProvider.googleCalendar.rawValue: ["google-previous"]
        ]
        Defaults[.selectedCalendarIDsByProviderMigrated] = true

        let eventKitStore = FakeEventStore(calendars: [eventKitCalendar])
        let googleStore = FakeEventStore()
        googleStore.stubbedSignInError = AuthError.refreshFailed
        let repository = CalendarRepository(providerName: .macOSEventKit) { provider in
            provider == .macOSEventKit ? eventKitStore : googleStore
        }
        let manager = CalendarSync(repository: repository, refreshInterval: 0)

        let result = await manager.changeEventStoreProvider(.googleCalendar)

        XCTAssertEqual(result, .failed("Google Calendar token refresh failed"))
        XCTAssertEqual(repository.activeProviderName, .macOSEventKit)
        XCTAssertEqual(Defaults[.eventStoreProvider], .macOSEventKit)
        XCTAssertEqual(Defaults[.selectedCalendarIDs], [eventKitCalendar.id])
        XCTAssertEqual(
            AppSettings.selectedCalendarIDs(for: .macOSEventKit),
            [eventKitCalendar.id]
        )
        XCTAssertEqual(
            AppSettings.selectedCalendarIDs(for: .googleCalendar),
            ["google-previous"]
        )
        XCTAssertFalse(manager.providerHealth.authRequired)
        XCTAssertTrue(manager.providerHealth.isStale)
    }

    /// Each source keeps its own calendar selection, and connecting a second
    /// source neither disturbs the first's selection nor disconnects it.
    func testConnectingASecondSourceKeepsBothProviderScopedSelections() async {
        let eventKitCalendar = MBCalendar(
            title: "EventKit",
            id: "eventkit",
            source: nil,
            email: nil,
            color: .black
        )
        let googleCalendar = MBCalendar(
            title: "Google",
            id: "google",
            source: nil,
            email: nil,
            color: .black,
            provider: .googleCalendar
        )
        Defaults[.eventStoreProvider] = .macOSEventKit
        Defaults[.selectedCalendarIDs] = [eventKitCalendar.id]
        Defaults[.selectedCalendarIDsByProvider] = [
            EventStoreProvider.macOSEventKit.rawValue: [eventKitCalendar.id]
        ]
        Defaults[.selectedCalendarIDsByProviderMigrated] = true

        let eventKitStore = FakeEventStore(calendars: [eventKitCalendar])
        let googleStore = FakeEventStore(calendars: [googleCalendar])
        let repository = CalendarRepository(providerName: .macOSEventKit) { provider in
            provider == .macOSEventKit ? eventKitStore : googleStore
        }
        let manager = CalendarSync(repository: repository, refreshInterval: 0)

        let googleResult = await manager.changeEventStoreProvider(.googleCalendar)
        XCTAssertEqual(googleResult, .success)
        XCTAssertEqual(
            repository.selection.providers,
            [.macOSEventKit, .googleCalendar],
            "connecting Google must not disconnect macOS Calendar")
        // EventKit stays the write-capable provider, so the legacy mirror key
        // keeps pointing at its selection.
        XCTAssertEqual(Defaults[.eventStoreProvider], .macOSEventKit)
        XCTAssertEqual(Defaults[.selectedCalendarIDs], [eventKitCalendar.id])

        AppSettings.setCalendarSelection(
            provider: .googleCalendar, id: googleCalendar.id, selected: true)

        XCTAssertEqual(
            AppSettings.selectedCalendarIDs(for: .googleCalendar),
            [googleCalendar.id]
        )
        XCTAssertEqual(
            AppSettings.selectedCalendarIDs(for: .macOSEventKit),
            [eventKitCalendar.id],
            "the other source's selection is untouched")
    }

    func testGoogleSwitchWithNoCalendarsPreservesCurrentProvider() async {
        let eventKitCalendar = MBCalendar(
            title: "EventKit",
            id: "eventkit",
            source: nil,
            email: nil,
            color: .black
        )
        Defaults[.eventStoreProvider] = .macOSEventKit
        Defaults[.selectedCalendarIDs] = [eventKitCalendar.id]

        let eventKitStore = FakeEventStore(calendars: [eventKitCalendar])
        let googleStore = FakeEventStore(calendars: [])
        let repository = CalendarRepository(providerName: .macOSEventKit) { provider in
            provider == .macOSEventKit ? eventKitStore : googleStore
        }
        let manager = CalendarSync(repository: repository, refreshInterval: 0)

        let result = await manager.changeEventStoreProvider(.googleCalendar)

        XCTAssertEqual(result, .failed("Google Calendar did not return any calendars"))
        XCTAssertEqual(repository.activeProviderName, .macOSEventKit)
        XCTAssertEqual(Defaults[.eventStoreProvider], .macOSEventKit)
        XCTAssertEqual(Defaults[.selectedCalendarIDs], [eventKitCalendar.id])
    }

    func testCalendarSyncStopCancelsActiveProviderOperations() {
        let store = FakeEventStore()
        let manager = CalendarSync(provider: store, refreshInterval: 0)

        manager.stop()

        XCTAssertEqual(store.cancelPendingOperationsCallCount, 1)
    }
}

@MainActor
final class FailedRefreshTests: BaseTestCase {
    private var cancellables = Set<AnyCancellable>()

    private let fakeCal = MBCalendar(
        title: "Cal", id: "calA", source: nil, email: nil, color: .black)

    func test_failedRefreshPreservesExistingCalendars() async throws {
        let store = FakeEventStore(calendars: [fakeCal])
        let manager = CalendarSync(provider: store, refreshInterval: 0)

        let initialExp = expectation(description: "initial calendars loaded")
        manager.$calendars.drop(while: \.isEmpty).first()
            .sink { _ in initialExp.fulfill() }
            .store(in: &cancellables)
        await fulfillment(of: [initialExp], timeout: 1.0)

        store.stubbedError = NSError(domain: "test", code: 1)

        let preservedExp = expectation(description: "calendars preserved after failure")
        manager.$calendars.dropFirst().first()
            .sink { cals in
                XCTAssertEqual(
                    cals, [self.fakeCal], "calendars must not be cleared on refresh failure")
                preservedExp.fulfill()
            }
            .store(in: &cancellables)

        try await manager.refreshSources()
        await fulfillment(of: [preservedExp], timeout: 1.0)
    }

    func test_failedRefreshPreservesExistingEvents() async throws {
        let fakeEvt = makeFakeEvent(
            id: "E1", start: Date().addingTimeInterval(60), end: Date().addingTimeInterval(3600))
        let store = FakeEventStore(calendars: [fakeCal], events: [fakeEvt])

        Defaults[.selectedCalendarIDs] = ["calA"]
        let manager = CalendarSync(provider: store, refreshInterval: 0)

        let initialExp = expectation(description: "initial events loaded")
        manager.$events.drop(while: \.isEmpty).first()
            .sink { _ in initialExp.fulfill() }
            .store(in: &cancellables)
        await fulfillment(of: [initialExp], timeout: 1.0)

        store.stubbedError = NSError(domain: "test", code: 1)

        let preservedExp = expectation(description: "events preserved after failure")
        manager.$events.dropFirst().first()
            .sink { evts in
                XCTAssertEqual(
                    evts, [fakeEvt], "events must be the exact preserved set after refresh failure")
                preservedExp.fulfill()
            }
            .store(in: &cancellables)

        try await manager.refreshSources()
        await fulfillment(of: [preservedExp], timeout: 1.0)
    }

    func test_failedInitialRefreshDoesNotCrash() {
        let store = FakeEventStore()
        store.stubbedError = NSError(domain: "test", code: 1)
        let manager = CalendarSync(provider: store, refreshInterval: 0)

        let exp = expectation(description: "brief wait after failed initial refresh")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(manager.calendars, [])
        XCTAssertEqual(manager.events, [])
    }
}

@MainActor
final class RefreshCoalescingTests: BaseTestCase {
    private var cancellables = Set<AnyCancellable>()

    func test_rapidTriggersResultInSingleFetch() async throws {
        let fakeCal = MBCalendar(title: "Cal", id: "calA", source: nil, email: nil, color: .black)
        let store = FakeEventStore(calendars: [fakeCal])
        store.fetchDelay = 0.2  // slow enough that the fetch is still running when the rapid triggers arrive

        let manager = CalendarSync(provider: store, refreshInterval: 0)

        let initialExp = expectation(description: "initial load")
        manager.$calendars.drop(while: \.isEmpty).first()
            .sink { _ in initialExp.fulfill() }
            .store(in: &cancellables)
        await fulfillment(of: [initialExp], timeout: 2.0)

        let countBefore = store.fetchCallCount

        // Fire three triggers in rapid succession — only the first should start a fetch
        manager.refreshSubject.send()
        manager.refreshSubject.send()
        manager.refreshSubject.send()

        // Wait longer than fetchDelay so the single fetch can complete
        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(
            store.fetchCallCount - countBefore, 1,
            "only one fetch should run despite three triggers")
    }
}

@MainActor
final class RefreshTriggerTests: BaseTestCase {

    private var cancellables = Set<AnyCancellable>()

    func test_eventsRefreshWhenShowEventsPeriodChanges() {
        // Fake store that can swap its stubbed events on the fly
        let first = makeFakeEvent(
            id: "P-A",
            start: .init(),
            end: .init().addingTimeInterval(60))
        let second = makeFakeEvent(
            id: "P-B",
            start: .init().addingTimeInterval(120),
            end: .init().addingTimeInterval(240))

        let store = FakeEventStore(events: [first])

        // Start with `.today`
        Defaults[.showEventsForPeriod] = .today
        let manager = CalendarSync(provider: store, refreshInterval: 0)

        // Expect initial publication with [first]
        let initialExp = expectation(description: "initial events")
        manager.$events
            .drop(while: \.isEmpty)
            .first()
            .sink { events in
                XCTAssertEqual(events, [first])
                initialExp.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [initialExp], timeout: 1.0)

        // Prepare expectation BEFORE flipping the Default
        let switchedExp = expectation(description: "events after period change")
        manager.$events
            .dropFirst()  // skip current value
            .first()
            .sink { events in
                XCTAssertEqual(events, [second])
                switchedExp.fulfill()
            }
            .store(in: &cancellables)

        // ↻ Mutate store, then toggle Default → Combine trigger fires
        store.stubbedEvents = [second]
        Defaults[.showEventsForPeriod] = .today_n_tomorrow

        wait(for: [switchedExp], timeout: 1.0)
    }

    func test_refreshSourcesPublishesEvents() async throws {
        let ev = makeFakeEvent(
            id: "R",
            start: .init(),
            end: .init().addingTimeInterval(60))
        let store = FakeEventStore(events: [ev])
        let manager = CalendarSync(provider: store, refreshInterval: 0)

        // Expectation BEFORE calling refreshSources()
        let exp = expectation(description: "events after manual refresh")
        manager.$events
            .dropFirst()  // skip the initial []
            .first()  // grab only the first non-empty publish
            .sink { events in
                XCTAssertEqual(events, [ev])
                exp.fulfill()
            }
            .store(in: &cancellables)

        // Act
        try await manager.refreshSources()

        await fulfillment(of: [exp], timeout: 1)
    }
}

@MainActor
final class ProviderHealthTests: BaseTestCase {
    private var cancellables = Set<AnyCancellable>()

    func test_successfulRefreshClearsError() async throws {
        let store = FakeEventStore(calendars: [
            MBCalendar(title: "C", id: "c1", source: nil, email: nil, color: .black)
        ])
        let manager = CalendarSync(provider: store, refreshInterval: 0)

        let exp = expectation(description: "health after success")
        manager.$providerHealth
            .drop(while: { $0.lastAttemptedRefresh == nil })
            .first()
            .sink { health in
                XCTAssertNotNil(health.lastSuccessfulRefresh)
                XCTAssertNil(health.lastErrorDescription)
                XCTAssertFalse(health.isStale)
                XCTAssertFalse(health.authRequired)
                exp.fulfill()
            }
            .store(in: &cancellables)

        await fulfillment(of: [exp], timeout: 1.0)
    }

    func test_failedRefreshSetsErrorAndPreservesLastSuccess() async throws {
        let store = FakeEventStore(calendars: [
            MBCalendar(title: "C", id: "c1", source: nil, email: nil, color: .black)
        ])
        let manager = CalendarSync(provider: store, refreshInterval: 0)

        let initialExp = expectation(description: "initial success")
        manager.$providerHealth
            .drop(while: { $0.lastSuccessfulRefresh == nil })
            .first()
            .sink { _ in initialExp.fulfill() }
            .store(in: &cancellables)
        await fulfillment(of: [initialExp], timeout: 1.0)

        let lastSuccess = manager.providerHealth.lastSuccessfulRefresh
        store.stubbedError = NSError(
            domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "network gone"])

        let failExp = expectation(description: "health after failure")
        manager.$providerHealth
            .dropFirst()
            .first()
            .sink { health in
                XCTAssertEqual(
                    health.lastSuccessfulRefresh, lastSuccess,
                    "prior success date must be preserved")
                XCTAssertNotNil(health.lastErrorDescription)
                XCTAssertTrue(health.isStale)
                XCTAssertFalse(health.authRequired)
                failExp.fulfill()
            }
            .store(in: &cancellables)

        try await manager.refreshSources()
        await fulfillment(of: [failExp], timeout: 1.0)
    }

    func test_authErrorSetsAuthRequired() {
        let attempted = Date()
        let health = ProviderHealth.failure(
            previous: ProviderHealth(lastSuccessfulRefresh: attempted.addingTimeInterval(-60)),
            attempted: attempted,
            error: AuthError.notSignedIn
        )

        XCTAssertTrue(health.authRequired)
        XCTAssertTrue(health.isStale)
        XCTAssertEqual(health.lastErrorDescription, "Google Calendar authorization is required")
    }

    func test_wrappedAuthErrorSetsAuthRequired() {
        let attempted = Date()
        let previousSuccess = attempted.addingTimeInterval(-60)
        let health = ProviderHealth.failure(
            previous: ProviderHealth(lastSuccessfulRefresh: previousSuccess),
            attempted: attempted,
            error: CalendarSyncError.eventFetchFailed(AuthError.notSignedIn)
        )

        XCTAssertTrue(health.authRequired)
        XCTAssertEqual(health.lastSuccessfulRefresh, previousSuccess)
    }

    func test_googleUnauthorizedErrorSetsAuthRequired() {
        let attempted = Date()
        let previousSuccess = attempted.addingTimeInterval(-60)
        let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
        let health = ProviderHealth.failure(
            previous: ProviderHealth(lastSuccessfulRefresh: previousSuccess),
            attempted: attempted,
            error: GoogleCalendarError.unauthorized(url)
        )

        XCTAssertTrue(health.authRequired)
        XCTAssertTrue(health.isStale)
        XCTAssertEqual(health.lastSuccessfulRefresh, previousSuccess)
    }

    func test_googleForbiddenCalendarDoesNotSetAuthRequired() {
        let attempted = Date()
        let previousSuccess = attempted.addingTimeInterval(-60)
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/bad/events")!
        let health = ProviderHealth.failure(
            previous: ProviderHealth(lastSuccessfulRefresh: previousSuccess),
            attempted: attempted,
            error: GoogleCalendarError.forbiddenCalendar(calendarID: "bad", url: url)
        )

        XCTAssertFalse(health.authRequired)
        XCTAssertTrue(health.isStale)
        XCTAssertEqual(health.lastSuccessfulRefresh, previousSuccess)
    }

    func test_genericFailureIsStaleButNotAuthRequired() {
        let attempted = Date()
        let previousSuccess = attempted.addingTimeInterval(-60)
        let health = ProviderHealth.failure(
            previous: ProviderHealth(lastSuccessfulRefresh: previousSuccess),
            attempted: attempted,
            error: NSError(domain: "network", code: -1009)
        )

        XCTAssertFalse(health.authRequired)
        XCTAssertTrue(health.isStale)
        XCTAssertEqual(health.lastSuccessfulRefresh, previousSuccess)
    }

    func test_refreshFailureIsStaleButDoesNotRequireReauthorization() {
        let attempted = Date()
        let previousSuccess = attempted.addingTimeInterval(-60)
        let health = ProviderHealth.failure(
            previous: ProviderHealth(lastSuccessfulRefresh: previousSuccess),
            attempted: attempted,
            error: AuthError.refreshFailed
        )

        XCTAssertFalse(health.authRequired)
        XCTAssertTrue(health.isStale)
        XCTAssertEqual(health.lastSuccessfulRefresh, previousSuccess)
        XCTAssertEqual(health.lastErrorDescription, "Google Calendar token refresh failed")
    }

    func test_eventFetchAuthFailurePreservesDataAndMarksAuthRequired() async throws {
        let calendar = MBCalendar(title: "C", id: "c1", source: nil, email: nil, color: .black)
        let event = makeFakeEvent(
            id: "auth",
            start: Date().addingTimeInterval(60),
            end: Date().addingTimeInterval(3600)
        )
        let store = FakeEventStore(calendars: [calendar], events: [event])
        Defaults[.selectedCalendarIDs] = [calendar.id]
        let manager = CalendarSync(provider: store, refreshInterval: 0)

        let initialExp = expectation(description: "initial success")
        manager.$providerHealth
            .drop(while: { $0.lastSuccessfulRefresh == nil })
            .first()
            .sink { _ in initialExp.fulfill() }
            .store(in: &cancellables)
        await fulfillment(of: [initialExp], timeout: 1.0)

        let lastSuccess = manager.providerHealth.lastSuccessfulRefresh
        store.stubbedEventsError = AuthError.notSignedIn

        let failureExp = expectation(description: "event fetch failure health")
        manager.$providerHealth
            .dropFirst()
            .first()
            .sink { health in
                XCTAssertEqual(health.lastSuccessfulRefresh, lastSuccess)
                XCTAssertTrue(health.authRequired)
                XCTAssertTrue(health.isStale)
                XCTAssertEqual(
                    health.lastErrorDescription, "Google Calendar authorization is required")
                failureExp.fulfill()
            }
            .store(in: &cancellables)

        try await manager.refreshSources()
        await fulfillment(of: [failureExp], timeout: 1.0)

        XCTAssertEqual(manager.calendars, [calendar])
        XCTAssertEqual(manager.events, [event])
    }

    func test_providerSwitchSignInFailureMarksProviderHealthAuthRequired() async throws {
        let calendar = MBCalendar(title: "C", id: "c1", source: nil, email: nil, color: .black)
        let store = FakeEventStore(calendars: [calendar])
        let repository = CalendarRepository(providerName: .macOSEventKit) { _ in store }
        let manager = CalendarSync(repository: repository, refreshInterval: 0)

        let initialExp = expectation(description: "initial success")
        manager.$providerHealth
            .drop(while: { $0.lastSuccessfulRefresh == nil })
            .first()
            .sink { _ in initialExp.fulfill() }
            .store(in: &cancellables)
        await fulfillment(of: [initialExp], timeout: 1.0)

        let lastSuccess = manager.providerHealth.lastSuccessfulRefresh
        store.stubbedSignInError = AuthError.notSignedIn

        let result = await manager.changeEventStoreProvider(.googleCalendar)

        XCTAssertEqual(
            result,
            .authRequired("Google Calendar authorization is required")
        )
        XCTAssertEqual(manager.providerHealth.lastSuccessfulRefresh, lastSuccess)
        XCTAssertNotNil(manager.providerHealth.lastAttemptedRefresh)
        XCTAssertEqual(
            manager.providerHealth.lastErrorDescription,
            "Google Calendar authorization is required"
        )
        XCTAssertTrue(manager.providerHealth.isStale)
        XCTAssertTrue(manager.providerHealth.authRequired)
    }
}

@MainActor
final class NewestEventChangeTests: BaseTestCase {
    func test_newestEventChangeReturnsMaxLastModifiedDate() {
        let older = Date(timeIntervalSince1970: 1_000_000)
        let newer = Date(timeIntervalSince1970: 2_000_000)
        let events = [
            makeFakeEvent(
                id: "A",
                start: Date(),
                end: Date().addingTimeInterval(60),
                lastModifiedDate: older
            ),
            makeFakeEvent(
                id: "B",
                start: Date(),
                end: Date().addingTimeInterval(60),
                lastModifiedDate: newer
            )
        ]

        XCTAssertEqual(CalendarSync.newestEventChange(in: events), newer)
    }

    func test_newestEventChangeIsNilForEmptyEventList() {
        XCTAssertNil(CalendarSync.newestEventChange(in: []))
    }

    func test_successfulRefreshThreadsNewestChangeOntoProviderHealth() async throws {
        let calendar = MBCalendar(title: "C", id: "c1", source: nil, email: nil, color: .black)
        let modified = Date(timeIntervalSince1970: 1_650_000_000)
        let event = makeFakeEvent(
            id: "sync",
            start: Date().addingTimeInterval(60),
            end: Date().addingTimeInterval(3600),
            lastModifiedDate: modified
        )
        let store = FakeEventStore(calendars: [calendar], events: [event])
        Defaults[.selectedCalendarIDs] = [calendar.id]
        let manager = CalendarSync(provider: store, refreshInterval: 0)

        let exp = expectation(description: "health carries newest change")
        manager.$providerHealth
            .drop(while: { $0.lastSyncedChange == nil })
            .first()
            .sink { health in
                XCTAssertEqual(health.lastSyncedChange, modified)
                exp.fulfill()
            }
            .store(in: &cancellables)

        await fulfillment(of: [exp], timeout: 1.0)
    }

    private var cancellables = Set<AnyCancellable>()
}
