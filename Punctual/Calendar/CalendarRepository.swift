//
//  CalendarRepository.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//
//  Modified for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026: hold a SET of
//  connected sources rather than one active provider. macOS Calendar and the
//  direct Google provider can now be connected at the same time; calendars and
//  events are fetched from every connected source and merged. A source that
//  fails no longer blanks out the ones that worked — see `fetchOutcome`.
//
import Combine
import Defaults
import EventKit
import Foundation

// MARK: - Date range helpers

func calendarDateRange(for period: ShowEventsForPeriod) -> (from: Date, to: Date) {
    let dateFrom = Calendar.current.startOfDay(for: Date())
    let dateTo: Date
    switch period {
    case .today:
        dateTo = Calendar.current.date(byAdding: .day, value: 1, to: dateFrom)!
    case .today_n_tomorrow,
         .today_n_tomorrow_next,
         .today_n_tomorrow_summary:
        dateTo = Calendar.current.date(byAdding: .day, value: 2, to: dateFrom)!
    }
    return (dateFrom, dateTo)
}

enum CalendarRepositoryError: LocalizedError {
    case noCalendars(EventStoreProvider)
    /// Every connected source failed. Carries the first underlying error so the
    /// existing auth-required and error-description handling still sees a real
    /// provider error rather than a wrapper.
    case allSourcesFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noCalendars(.googleCalendar):
            return "Google Calendar did not return any calendars"
        case .noCalendars(.macOSEventKit):
            return "macOS Calendar did not return any calendars"
        case let .allSourcesFailed(error):
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// The result of fetching across every connected source: what came back, and
/// which sources failed while others succeeded.
public struct CalendarFetchOutcome<Element> {
    public var elements: [Element]
    public var failures: [CalendarSourceFailure]
}

/// Owns the connected calendar providers and exposes calendar/event fetching.
///
/// `CalendarSync` delegates to `CalendarRepository` for all provider-specific
/// work so that source management is in one place.
@MainActor
public final class CalendarRepository {
    // MARK: - Connected sources

    /// Which sources are connected. Never empty.
    public private(set) var selection: CalendarSourceSelection

    /// The provider that handles WRITES and stands in wherever a single
    /// provider identity is still required (per-provider calendar selection,
    /// the diagnostics report, EventKit-only affordances). EventKit whenever it
    /// is connected, because it is the only writable source.
    public var activeProviderName: EventStoreProvider {
        selection.writeSource?.provider ?? selection.providers.first ?? .macOSEventKit
    }

    /// The store behind `activeProviderName`.
    public var activeProvider: EventStore { store(for: activeProviderName) }

    /// Live stores, one per provider, created on demand and then reused. Held
    /// even for sources that are currently disconnected so that reconnecting
    /// does not discard an in-memory auth state.
    private var stores: [EventStoreProvider: EventStore] = [:]
    private let storeFactory: (EventStoreProvider) -> EventStore
    private let observesSystemStoreChanges: Bool
    private var pendingProvider: EventStore?

    /// Fires when the EKEventStore changes (macOS Calendar App only).
    let storeChanged = PassthroughSubject<Void, Never>()
    private var storeChangeCancellable: AnyCancellable?

    // MARK: - Initialization

    public init(selection: CalendarSourceSelection) {
        self.selection = selection
        self.storeFactory = CalendarRepository.makeStore(for:)
        self.observesSystemStoreChanges = true
        observeStoreChanges()
    }

    public convenience init(providerName: EventStoreProvider) {
        self.init(selection: CalendarSourceSelection(providers: [providerName]))
    }

    // MARK: - Source management

    /// Connects `providerName`, ADDING it to the connected set rather than
    /// replacing what is already there. Signing in and listing calendars happen
    /// before the set changes, so a failed connection leaves the previous state
    /// untouched.
    ///
    /// Re-connecting an already-connected source is how re-authorization works:
    /// pass `signOut: true` to force a fresh sign-in.
    @discardableResult
    public func connect(
        _ providerName: EventStoreProvider,
        signOut: Bool = false
    ) async throws -> [MBCalendar] {
        let candidate = store(for: providerName)
        pendingProvider = candidate
        defer { pendingProvider = nil }

        if signOut {
            await (candidate as? AuthenticatedEventStore)?.signOut()
        }

        try await (candidate as? AuthenticatedEventStore)?.signIn(forcePrompt: false)
        let calendars = try await candidate.fetchAllCalendars()
        if providerName == .googleCalendar, calendars.isEmpty {
            throw CalendarRepositoryError.noCalendars(providerName)
        }

        selection = selection.enabling(providerName.sourceKind)
        observeStoreChanges()
        return try await fetchAllCalendars().elements
    }

    /// Disconnects a source. Refused when it is the last one connected — see
    /// `CalendarSourceSelection` on why zero sources is not a modelled state.
    ///
    /// `signOut` discards the provider's stored credentials. Defaulting it to
    /// false means disconnecting and reconnecting is not a fresh OAuth round
    /// trip; signing out is a separate, deliberate action.
    public func disconnect(_ providerName: EventStoreProvider, signOut: Bool = false) async {
        guard selection.canDisable(providerName.sourceKind) else { return }
        selection = selection.disabling(providerName.sourceKind)

        if let store = stores[providerName] {
            if signOut {
                await (store as? AuthenticatedEventStore)?.signOut()
            }
            store.cancelPendingOperations()
        }
        observeStoreChanges()
    }

    /// Replaces the connected set wholesale, connecting and disconnecting as
    /// needed to reach `target`. Used by the source toggles.
    public func applySelection(_ target: CalendarSourceSelection) async throws {
        for provider in selection.providers where !target.isEnabled(provider) {
            await disconnect(provider)
        }
        for provider in target.providers where !selection.isEnabled(provider) {
            try await connect(provider)
        }
    }

    public func stop() {
        storeChangeCancellable?.cancel()
        storeChangeCancellable = nil
        if let pendingProvider,
           !stores.values.contains(where: { $0 === pendingProvider }) {
            pendingProvider.cancelPendingOperations()
        }
        pendingProvider = nil
        for store in stores.values {
            store.cancelPendingOperations()
        }
    }

    // MARK: - Fetch

    /// Calendars from every connected source, merged in source display order.
    public func fetchAllCalendars() async throws -> CalendarFetchOutcome<MBCalendar> {
        try await gather { store, _ in try await store.fetchAllCalendars() }
    }

    public func fetchEventsForDateRange(
        for calendars: [MBCalendar],
        from dateFrom: Date,
        to dateTo: Date
    ) async throws -> CalendarFetchOutcome<MBEvent> {
        // Each store is handed only the calendars it owns. A source with none
        // selected is still called, exactly as the single-provider code called
        // the active provider with an empty list: both stores return no events
        // for an empty selection, and short-circuiting here instead would make
        // "no calendars ticked" a different code path than "none matched".
        try await gather { store, provider in
            let owned = calendars.filter { $0.provider == provider }
            return try await store.fetchEventsForDateRange(for: owned, from: dateFrom, to: dateTo)
        }
    }

    /// The user's selected calendars out of `allCalendars`, across every
    /// connected source.
    ///
    /// Calendar selection is stored PER PROVIDER, so each source's calendars are
    /// matched against that source's own selected IDs. Filtering the merged list
    /// against a single provider's ID list — which is what the single-provider
    /// code did — silently drops every calendar belonging to the other source.
    public func selectedCalendars(from allCalendars: [MBCalendar]) -> [MBCalendar] {
        let selectedByProvider = Dictionary(
            uniqueKeysWithValues: selection.providers.map {
                ($0, Set(AppSettings.selectedCalendarIDs(for: $0)))
            }
        )
        return allCalendars.filter { calendar in
            selectedByProvider[calendar.provider]?.contains(calendar.id) ?? false
        }
    }

    /// Fetches events for the currently configured display period and selected
    /// calendars, across every connected source.
    public func fetchCurrentPeriodEvents(
        fromAllCalendars allCalendars: [MBCalendar]
    ) async throws -> CalendarFetchOutcome<MBEvent> {
        let (dateFrom, dateTo) = calendarDateRange(for: Defaults[.showEventsForPeriod])
        return try await fetchEventsForDateRange(
            for: selectedCalendars(from: allCalendars),
            from: dateFrom,
            to: dateTo
        )
    }

    public func refreshSources() async {
        for provider in selection.providers {
            await store(for: provider).refreshSources()
        }
    }

    /// Runs `work` against every connected source and merges the results.
    ///
    /// A source that throws is recorded as a partial failure rather than
    /// aborting the whole fetch: with two sources connected, an expired Google
    /// token must not blank out the macOS Calendar events that fetched fine.
    /// Only when EVERY source fails does this throw, so a genuinely broken
    /// single-source install still surfaces its error exactly as before.
    ///
    /// Sources are walked in display order and awaited one at a time. That is
    /// deliberate: fetches are network- or XPC-bound and each provider already
    /// parallelizes internally, while a task group here would make the merged
    /// order non-deterministic and cost more than it saves for two sources.
    private func gather<Element>(
        _ work: (EventStore, EventStoreProvider) async throws -> [Element]
    ) async throws -> CalendarFetchOutcome<Element> {
        var elements: [Element] = []
        var failures: [CalendarSourceFailure] = []
        var firstError: Error?

        let providers = selection.providers
        for provider in providers {
            do {
                elements += try await work(store(for: provider), provider)
            } catch {
                if firstError == nil { firstError = error }
                failures.append(ProviderHealth.sourceFailure(provider: provider, error: error))
                let description = String(describing: error)
                PunctualLogger.calendar.error(
                    "Source \(provider.rawValue, privacy: .public) failed: \(description, privacy: .private)"
                )
            }
        }

        if failures.count == providers.count, let firstError {
            throw providers.count == 1
                ? firstError
                : CalendarRepositoryError.allSourcesFailed(firstError)
        }
        return CalendarFetchOutcome(elements: elements, failures: failures)
    }

    // MARK: - Authenticated helpers

    public func signIn(forcePrompt: Bool = false) async throws {
        try await (activeProvider as? AuthenticatedEventStore)?.signIn(forcePrompt: forcePrompt)
    }

    public func signOut() async {
        await (activeProvider as? AuthenticatedEventStore)?.signOut()
    }

    /// Forwards an OAuth callback URL to whichever store is mid-authorization.
    ///
    /// Returns `true` if the URL was consumed.
    @discardableResult
    public func resumeAuthorizationFlow(with url: URL) -> Bool {
        let candidates: [EventStore] = [pendingProvider].compactMap { $0 } + Array(stores.values)
        for candidate in candidates {
            guard let store = candidate as? GCEventStore,
                  let flow = store.currentAuthorizationFlow else { continue }
            if flow.resumeExternalUserAgentFlow(with: url) { return true }
        }
        return false
    }

    #if DEBUG
        /// Test-only: inject deterministic stores for source switching without
        /// creating EventKit/Google singletons.
        public convenience init(
            providerName: EventStoreProvider,
            storeFactory: @escaping (EventStoreProvider) -> EventStore
        ) {
            self.init(
                selection: CalendarSourceSelection(providers: [providerName]),
                storeFactory: storeFactory
            )
        }

        /// Test-only: start with SEVERAL sources already connected, without
        /// driving each one through `connect`.
        public init(
            selection: CalendarSourceSelection,
            storeFactory: @escaping (EventStoreProvider) -> EventStore
        ) {
            self.selection = selection
            self.storeFactory = storeFactory
            self.observesSystemStoreChanges = false
            // Realize the initially connected stores up front. Lazy creation
            // would leave `stores` empty until the first fetch, so `stop()`
            // before any fetch would cancel nothing.
            for provider in selection.providers {
                _ = store(for: provider)
            }
        }

        /// Test-only: inject a pre-built store without creating system singletons.
        public init(store: EventStore) {
            self.selection = CalendarSourceSelection(providers: [.macOSEventKit])
            self.storeFactory = { _ in store }
            self.observesSystemStoreChanges = false
            stores[.macOSEventKit] = store
        }
    #endif

    // MARK: - Private helpers

    /// Returns the live store for a provider, creating it on first use.
    private func store(for providerName: EventStoreProvider) -> EventStore {
        if let existing = stores[providerName] { return existing }
        let created = storeFactory(providerName)
        stores[providerName] = created
        return created
    }

    private static func makeStore(for providerName: EventStoreProvider) -> EventStore {
        switch providerName {
        case .macOSEventKit: return EKEventStore.shared
        case .googleCalendar: return GCEventStore.shared
        }
    }

    /// Watches EventKit for external changes whenever macOS Calendar is one of
    /// the connected sources. Google has no equivalent push signal; it relies on
    /// the periodic refresh.
    private func observeStoreChanges() {
        storeChangeCancellable?.cancel()
        storeChangeCancellable = nil
        guard observesSystemStoreChanges, selection.isEnabled(CalendarSourceKind.macOSEventKit) else { return }
        let store = EKEventStore.shared
        storeChangeCancellable = NotificationCenter.default
            .publisher(for: .EKEventStoreChanged, object: store)
            .map { _ in () }
            .sink { [weak self] in self?.storeChanged.send() }
    }
}
