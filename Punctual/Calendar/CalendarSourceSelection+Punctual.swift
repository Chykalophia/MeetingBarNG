//
//  CalendarSourceSelection+MeetingBar.swift
//  MeetingBarNG
//
//  Bridges the hostless `CalendarSourceKind` to the app layer's
//  `EventStoreProvider`, the same way `DiagnosticsReport+MeetingBar` bridges
//  `DiagnosticsProvider`. The rules live in the hostless type; this file only
//  translates, and answers "can this build actually use that source".
//

import AppKit
import Foundation

extension CalendarSourceKind {
    init(provider: EventStoreProvider) {
        switch provider {
        case .macOSEventKit: self = .macOSEventKit
        case .googleCalendar: self = .googleCalendar
        }
    }

    var provider: EventStoreProvider {
        switch self {
        case .macOSEventKit: return .macOSEventKit
        case .googleCalendar: return .googleCalendar
        }
    }

    /// Whether the source can actually be signed into right now. macOS Calendar
    /// always can; Google needs an OAuth client, from either the build
    /// (`XCConfig/GoogleSecrets.xcconfig`) or the user's own entered in
    /// Preferences. Keeping a source CONNECTED that cannot possibly sign in is
    /// worse than dropping it, which is what `availableOnly` uses this for.
    @MainActor
    var isAvailableInThisBuild: Bool {
        switch self {
        case .macOSEventKit: return true
        case .googleCalendar: return GoogleOAuthConfig.effectiveClient != nil
        }
    }
}

extension EventStoreProvider {
    var sourceKind: CalendarSourceKind { CalendarSourceKind(provider: self) }
}

extension CalendarSourceSelection {
    init(providers: [EventStoreProvider]) {
        self.init(enabled: providers.map(CalendarSourceKind.init(provider:)))
    }

    /// Enabled sources as app-layer providers, in display order.
    var providers: [EventStoreProvider] {
        enabled.map(\.provider)
    }

    func isEnabled(_ provider: EventStoreProvider) -> Bool {
        isEnabled(provider.sourceKind)
    }

    /// The selection filtered down to what this build can actually reach.
    @MainActor
    var usable: CalendarSourceSelection {
        availableOnly(\.isAvailableInThisBuild)
    }
}
