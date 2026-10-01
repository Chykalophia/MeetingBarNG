//
//  ProviderHealth.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 24.04.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//
//  Modified for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026:
//  carry `lastSyncedChange` — the newest `lastModifiedDate` across the fetched
//  events — so the Calendars tab can surface "most recent calendar change" as a
//  staleness signal (macOS Calendar serves stale data silently when an account's
//  sync stalls). Preserved across failed refreshes like `lastSuccessfulRefresh`.
//
import Foundation

/// One source failing while another succeeded.
///
/// With a single provider a failed fetch was the whole story, so it could go
/// straight into `lastErrorDescription`. With two sources connected, Google's
/// token expiring must not blank out the macOS Calendar events that fetched
/// perfectly well — but it must not pass silently either, which is exactly how a
/// calendar app loses the user's trust. Partial failures are therefore reported
/// alongside a successful refresh rather than instead of one.
public struct CalendarSourceFailure: Equatable, Sendable {
    public let provider: EventStoreProvider
    public let errorDescription: String
    public let authRequired: Bool

    public init(provider: EventStoreProvider, errorDescription: String, authRequired: Bool) {
        self.provider = provider
        self.errorDescription = errorDescription
        self.authRequired = authRequired
    }
}

public struct ProviderHealth: Equatable {
    public var lastSuccessfulRefresh: Date?
    public var lastAttemptedRefresh: Date?
    public var lastErrorDescription: String?
    /// True when the displayed data comes from a preserved snapshot, not the latest fetch attempt.
    public var isStale: Bool
    public var authRequired: Bool
    /// Sources that failed while at least one other succeeded. Empty in the
    /// common case, and always empty when only one source is connected — a lone
    /// source's failure is a plain failure, reported through
    /// `lastErrorDescription` as before.
    public var degradedSources: [CalendarSourceFailure] = []
    /// Newest `MBEvent.lastModifiedDate` across the last fetched event set.
    /// A signal the user can eyeball for staleness: if it reads "4 days ago"
    /// when they edited an event today, macOS Calendar's own sync has stalled.
    /// EventKit has no "credentials expired" API, so this is surfaced (not
    /// auto-judged) alongside a re-authenticate affordance.
    public var lastSyncedChange: Date?

    public init(
        lastSuccessfulRefresh: Date? = nil,
        lastAttemptedRefresh: Date? = nil,
        lastErrorDescription: String? = nil,
        isStale: Bool = false,
        authRequired: Bool = false,
        lastSyncedChange: Date? = nil,
        degradedSources: [CalendarSourceFailure] = []
    ) {
        self.lastSuccessfulRefresh = lastSuccessfulRefresh
        self.lastAttemptedRefresh = lastAttemptedRefresh
        self.lastErrorDescription = lastErrorDescription
        self.isStale = isStale
        self.authRequired = authRequired
        self.lastSyncedChange = lastSyncedChange
        self.degradedSources = degradedSources
    }
}

extension ProviderHealth {
    static func success(
        attempted: Date,
        lastSyncedChange: Date? = nil,
        degradedSources: [CalendarSourceFailure] = []
    ) -> ProviderHealth {
        ProviderHealth(
            lastSuccessfulRefresh: attempted,
            lastAttemptedRefresh: attempted,
            lastErrorDescription: nil,
            isStale: false,
            authRequired: false,
            lastSyncedChange: lastSyncedChange,
            degradedSources: degradedSources
        )
    }

    /// Builds a partial failure from a source's underlying error, reusing the
    /// same description and auth-detection rules a total failure gets.
    static func sourceFailure(provider: EventStoreProvider, error: Error) -> CalendarSourceFailure {
        CalendarSourceFailure(
            provider: provider,
            errorDescription: errorDescription(error),
            authRequired: isAuthRequired(error)
        )
    }

    static func failure(
        previous: ProviderHealth,
        attempted: Date,
        error: Error
    ) -> ProviderHealth {
        ProviderHealth(
            lastSuccessfulRefresh: previous.lastSuccessfulRefresh,
            lastAttemptedRefresh: attempted,
            lastErrorDescription: Self.errorDescription(error),
            isStale: true,
            authRequired: Self.isAuthRequired(error),
            // Preserve the last-known newest change so the "most recent change"
            // line keeps its value while showing preserved (stale) data.
            lastSyncedChange: previous.lastSyncedChange
        )
    }

    private static func errorDescription(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return error.localizedDescription
    }

    private static func isAuthRequired(_ error: Error) -> Bool {
        if let authError = error as? AuthError {
            switch authError {
            case .notSignedIn:
                return true
            case .cancelled, .refreshFailed, .notConfigured:
                return false
            }
        }

        if let googleError = error as? GoogleCalendarError {
            switch googleError {
            case .unauthorized:
                return true
            case .forbiddenCalendar, .httpStatus, .missingItems:
                return false
            }
        }

        switch error {
        case let CalendarSyncError.calendarAccessFailed(underlying):
            return isAuthRequired(underlying)
        case let CalendarSyncError.eventFetchFailed(underlying):
            return isAuthRequired(underlying)
        default:
            return false
        }
    }
}
