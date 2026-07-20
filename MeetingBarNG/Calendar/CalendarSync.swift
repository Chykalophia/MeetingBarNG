//
//  CalendarSync.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//
//  Modified for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026:
//  add a debounced aggressive force-sync (`forceSyncIfDebounceElapsed`) that
//  proactively nudges macOS to sync (EventKit `refreshSourcesIfNecessary()`,
//  which also makes macOS surface its own stalled-sync error sooner) on
//  status-menu open / system wake / unlock, at most once per ~30s; and compute
//  `newestEventChange` (the newest event `lastModifiedDate`) each refresh and
//  thread it onto `ProviderHealth.lastSyncedChange` for the Calendars-tab
//  staleness signal. Also collapse cross-calendar duplicate events (same event
//  arriving on two selected calendars/accounts) via `EventDeduplication`,
//  gated on `Defaults[.deduplicateEvents]`.
//
import Cocoa
import Combine
import Defaults
import Foundation
import UserNotifications

public enum CalendarSyncError: LocalizedError {
    case eventStoreNotAvailable
    case calendarAccessFailed(Error)
    case eventFetchFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .eventStoreNotAvailable:
            return "Event store is not available"
        case let .calendarAccessFailed(error), let .eventFetchFailed(error):
            return error.localizedDescription
        }
    }
}

public enum ProviderSelectionResult: Equatable {
    case success
    case cancelled
    case authRequired(String)
    case failed(String)
}

@MainActor
public class CalendarSync: ObservableObject {
    @Published public private(set) var calendars: [MBCalendar] = []
    @Published public private(set) var events: [MBEvent] = []
    @Published public private(set) var providerHealth = ProviderHealth()

    var repository: CalendarRepository
    private let refreshInterval: TimeInterval
    private var cancellables = Set<AnyCancellable>()
    /// Held separately from `cancellables` so we can cancel the previous
    /// repository-store subscription when switching providers, instead of
    /// stacking up additional sinks on every switch.
    private var storeChangeCancellable: AnyCancellable?
    private var storeChangeRefreshTask: Task<Void, Never>?
    private var refreshCycleTask: Task<Void, Never>?
    private var providerGeneration = 0
    let refreshSubject = PassthroughSubject<Void, Never>()

    // MARK: - Initialization

    public init(refreshInterval: TimeInterval = 180) async {
        self.refreshInterval = refreshInterval
        AppSettings.migrateSelectedCalendarsByProviderIfNeeded()
        repository = CalendarRepository(providerName: Defaults[.eventStoreProvider])
        await configureProvider(Defaults[.eventStoreProvider])
        setupPublishers()
        refreshSubject.send() // initial load
    }

    public func changeEventStoreProvider(
        _ newProvider: EventStoreProvider,
        withSignOut: Bool = false
    ) async -> ProviderSelectionResult {
        do {
            let newCalendars = try await repository.switchProvider(
                to: newProvider,
                signOutCurrent: withSignOut
            )
            refreshCycleTask?.cancel()
            refreshCycleTask = nil
            AppSettings.setEventStoreProvider(newProvider)
            providerGeneration += 1
            calendars = newCalendars
            events = []
            providerHealth = ProviderHealth()
            subscribeToRepositoryStoreChanges()
            refreshSubject.send()
            return .success
        } catch {
            let attempted = Date()
            let errorDescription = String(describing: error)
            MeetingBarLogger.calendar.error(
                "Provider switch sign-in failed: \(errorDescription, privacy: .private)"
            )
            providerHealth = ProviderHealth.failure(
                previous: providerHealth,
                attempted: attempted,
                error: error
            )
            return providerSelectionResult(for: error)
        }
    }

    private func providerSelectionResult(for error: Error) -> ProviderSelectionResult {
        if let authError = error as? AuthError {
            switch authError {
            case .cancelled:
                return .cancelled
            case .notSignedIn:
                return .authRequired(error.localizedDescription)
            case .refreshFailed:
                return .failed(error.localizedDescription)
            case .notConfigured:
                return .failed(error.localizedDescription)
            }
        }
        if case .unauthorized = error as? GoogleCalendarError {
            return .authRequired(error.localizedDescription)
        }
        return .failed(error.localizedDescription)
    }

    private func configureProvider(_ providerName: EventStoreProvider) async {
        subscribeToRepositoryStoreChanges()
    }

    private func subscribeToRepositoryStoreChanges() {
        // Cancel any previous subscription before re-attaching to the (new)
        // repository. Without this, switching providers would stack sinks
        // and trigger N refreshes per store change.
        storeChangeCancellable?.cancel()
        storeChangeCancellable = repository.storeChanged
            .sink { [weak self] in
                guard let self else { return }
                self.storeChangeRefreshTask?.cancel()
                self.storeChangeRefreshTask = Task { [weak self] in
                    do {
                        try await self?.refreshSources()
                    } catch {
                        let errorDescription = String(describing: error)
                        MeetingBarLogger.calendar.error(
                            "Calendar reload after store change failed: \(errorDescription, privacy: .private)"
                        )
                    }
                }
            }
    }

    public func stop() {
        forcedSyncTask?.cancel()
        forcedSyncTask = nil
        storeChangeRefreshTask?.cancel()
        storeChangeRefreshTask = nil
        refreshCycleTask?.cancel()
        refreshCycleTask = nil
        storeChangeCancellable?.cancel()
        storeChangeCancellable = nil
        cancellables.removeAll()
        repository.stop()
    }

    public func refreshSources() async throws {
        await repository.refreshSources()
        refreshSubject.send()
    }

    // MARK: - Aggressive force-sync

    /// Minimum spacing between forced syncs. Menu-open / wake / unlock can each
    /// fire in quick succession; without this guard, opening the menu repeatedly
    /// would hammer EventKit's `refreshSourcesIfNecessary()`.
    private static let forcedSyncDebounceInterval: TimeInterval = 30
    /// Timestamp of the last forced sync we actually dispatched.
    private var lastForcedSyncAt: Date?
    private var forcedSyncTask: Task<Void, Never>?

    /// Aggressively nudge the underlying provider to sync now — for EventKit this
    /// reaches `EKEventStore.refreshSourcesIfNecessary()`, which both pulls fresh
    /// data and makes macOS surface its own stalled-sync error sooner — then
    /// re-fetch via `refreshSources()`. Debounced to at most one dispatch per
    /// `forcedSyncDebounceInterval` so status-menu-open spam and back-to-back
    /// wake/unlock notifications don't overload EventKit. The periodic 180s timer
    /// and the manual Refresh path are unaffected.
    public func forceSyncIfDebounceElapsed(now: Date = Date()) {
        if let lastForcedSyncAt,
           now.timeIntervalSince(lastForcedSyncAt) < Self.forcedSyncDebounceInterval {
            MeetingBarLogger.calendar.debug("Skipping forced calendar sync (debounced)")
            return
        }
        lastForcedSyncAt = now
        MeetingBarLogger.calendar.info("Forcing calendar sync (nudging provider to refresh sources)")
        forcedSyncTask?.cancel()
        forcedSyncTask = Task { [weak self] in
            do {
                try await self?.refreshSources()
            } catch {
                let errorDescription = String(describing: error)
                MeetingBarLogger.calendar.error(
                    "Forced calendar sync failed: \(errorDescription, privacy: .private)"
                )
            }
        }
    }

    /// Newest `lastModifiedDate` across the given events, or `nil` when none of
    /// them carry a modification date (or there are no events). Pure so it can be
    /// unit-tested and threaded onto `ProviderHealth.lastSyncedChange`.
    static func newestEventChange(in events: [MBEvent]) -> Date? {
        events.compactMap(\.lastModifiedDate).max()
    }

    /// Fetches events for the selected calendars within the specified date range
    private func fetchEvents(fromCalendars: [MBCalendar]) async throws -> [MBEvent] {
        let rawEvents: [MBEvent]
        do {
            rawEvents = try await repository.fetchCurrentPeriodEvents(fromAllCalendars: fromCalendars)
        } catch {
            throw CalendarSyncError.eventFetchFailed(error)
        }

        // First collapse exact per-occurrence duplicates (same internal id).
        let deduplicatedEvents = Array(Dictionary(
            rawEvents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        ).values)

        // Then collapse cross-calendar duplicates: the same underlying event
        // arriving on two selected calendars/accounts survives the id-keyed pass
        // (each copy has its own per-occurrence id) but shares an external
        // identifier, so the pure deduplicator catches it. Opt-out preserved.
        let events: [MBEvent]
        if Defaults[.deduplicateEvents] {
            let candidates = deduplicatedEvents.enumerated().map { index, event in
                DeduplicationEvent(
                    sourceIndex: index,
                    externalIdentifier: event.externalIdentifier,
                    title: event.title,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay
                )
            }
            events = EventDeduplication.keptIndices(candidates).map { deduplicatedEvents[$0] }
        } else {
            events = deduplicatedEvents
        }

        if !AppSettings.current.events.dismissedEvents.isEmpty {
            AppSettings.refreshDismissedEvents(using: events)
        }
        return events.filtered().sorted { $0.startDate < $1.startDate }
    }

    private func setupPublishers() {
        // A) Defaults changes as an “empty” trigger
        let defaultsPub = Defaults.publisher(keys:
            .selectedCalendarIDs,
            .showEventsForPeriod,
            .customRegexes,
            .declinedEventsAppereance,
            .showPendingEvents,
            .showTentativeEvents,
            .allDayEvents,
            .nonAllDayEvents, options: []).map { _ in () }.eraseToAnyPublisher()

        // B) Periodic timer trigger
        let timerPub: AnyPublisher<Void, Never>
        if refreshInterval > 0 {
            timerPub = Timer
                .publish(every: refreshInterval, on: .main, in: .common)
                .autoconnect()
                .map { _ in () }
                .eraseToAnyPublisher()
        } else {
            timerPub = Empty().eraseToAnyPublisher()
        }

        // C) Manual trigger
        let manualPub = refreshSubject.eraseToAnyPublisher()

        // D) Merge all triggers; throttle drops bursts.
        // Throttle (not debounce) so the first trigger in a window passes through
        // immediately — manual refresh feels instant — while subsequent rapid
        // triggers (e.g. several Defaults changes in one preferences update) are
        // collapsed into a single fetch. debounce would also delay a fast periodic
        // timer indefinitely if its interval is shorter than the debounce window.
        let trigger = Publishers.Merge3(defaultsPub, timerPub, manualPub)
            .throttle(for: .milliseconds(200), scheduler: RunLoop.main, latest: false)

        // E) When any fires, fetch calendars & events.
        // flatMap(maxPublishers: .max(1)) serializes fetches so at most one runs
        // at a time; if another trigger arrives during a fetch, it queues exactly once.
        trigger
            .flatMap(maxPublishers: .max(1)) { [weak self] _ -> AnyPublisher<RefreshResult, Never> in
                guard let self = self else {
                    return Just(
                        RefreshResult(
                            calendars: [],
                            events: [],
                            health: ProviderHealth(),
                            providerGeneration: -1
                        )
                    ).eraseToAnyPublisher()
                }
                // Capture current state on the main thread before entering the async Task.
                // On failure we republish these so the UI keeps showing last known data.
                let preservedCalendars = self.calendars
                let preservedEvents = self.events
                let previousHealth = self.providerHealth
                let providerGeneration = self.providerGeneration
                return Deferred {
                    Future<RefreshResult, Never> { promise in
                        self.refreshCycleTask = Task { [weak self] in
                            guard let self else { return }
                            let attempted = Date()
                            do {
                                let cals = try await self.repository.fetchAllCalendars()
                                try Task.checkCancellation()
                                let evts = try await self.fetchEvents(fromCalendars: cals)
                                let health = ProviderHealth.success(
                                    attempted: attempted,
                                    lastSyncedChange: Self.newestEventChange(in: evts)
                                )
                                promise(.success(RefreshResult(
                                    calendars: cals,
                                    events: evts,
                                    health: health,
                                    providerGeneration: providerGeneration
                                )))
                            } catch {
                                let errorDescription = String(describing: error)
                                MeetingBarLogger.calendar.error(
                                    "Event refresh failed: \(errorDescription, privacy: .private)"
                                )
                                let health = ProviderHealth.failure(
                                    previous: previousHealth,
                                    attempted: attempted,
                                    error: error
                                )
                                promise(.success(RefreshResult(
                                    calendars: preservedCalendars,
                                    events: preservedEvents,
                                    health: health,
                                    providerGeneration: providerGeneration
                                )))
                            }
                        }
                    }
                }
                .eraseToAnyPublisher()
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] result in
                guard let self,
                      result.providerGeneration == self.providerGeneration else {
                    return
                }
                self.calendars = result.calendars
                self.events = result.events
                self.providerHealth = result.health
            }
            .store(in: &cancellables)
    }

    /// Result of a single refresh cycle. On failure, `calendars` and `events`
    /// are the preserved last-known-good values so the UI keeps showing them.
    private struct RefreshResult {
        let calendars: [MBCalendar]
        let events: [MBEvent]
        let health: ProviderHealth
        let providerGeneration: Int
    }

    #if DEBUG
        /// Test-only initializer: inject your own store and skip
        /// the async system-store configuration.
        public init(provider: EventStore,
                    refreshInterval: TimeInterval = 0) {
            self.refreshInterval = refreshInterval
            self.repository = CalendarRepository(store: provider)
            setupPublishers()
            refreshSubject.send()
        }

        /// Test-only initializer: inject a repository that can switch between
        /// deterministic fake providers.
        public init(repository: CalendarRepository,
                    refreshInterval: TimeInterval = 0) {
            self.refreshInterval = refreshInterval
            self.repository = repository
            subscribeToRepositoryStoreChanges()
            setupPublishers()
            refreshSubject.send()
        }
    #endif
}
