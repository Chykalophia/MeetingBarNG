//
//  PreferencesPresentation.swift
//  MeetingBar
//

import Foundation

struct CalendarSourcePresentation: Equatable, Identifiable {
    let provider: EventStoreProvider
    let titleKey: String
    let descriptionKey: String
    let dataSourceKey: String
    let accountScopeKey: String
    let authorizationDescriptionKey: String
    let systemImage: String

    var id: EventStoreProvider { provider }

    // Option A (MeetingBarNG): ship the macOS Calendar provider only — it
    // already surfaces Google/iCloud/Exchange accounts synced on this Mac, and
    // the native Google provider needs OAuth credentials this build doesn't
    // carry. `make(for: .googleCalendar)` is retained for any install still on
    // the Google provider from a prior build.
    static let all: [CalendarSourcePresentation] = [
        make(for: .macOSEventKit)
    ]

    static func make(for provider: EventStoreProvider) -> CalendarSourcePresentation {
        switch provider {
        case .macOSEventKit:
            CalendarSourcePresentation(
                provider: provider,
                titleKey: "onboarding_apple_calendar_title",
                descriptionKey: "onboarding_apple_calendar_description",
                dataSourceKey: "access_screen_provider_macos_data_source",
                accountScopeKey: "access_screen_provider_macos_number_of_accounts",
                authorizationDescriptionKey: "onboarding_authorization_apple_description",
                systemImage: "calendar"
            )
        case .googleCalendar:
            CalendarSourcePresentation(
                provider: provider,
                titleKey: "onboarding_google_calendar_title",
                descriptionKey: "onboarding_google_calendar_description",
                dataSourceKey: "access_screen_provider_gcalendar_data_source",
                accountScopeKey: "access_screen_provider_gcalendar_number_of_accounts",
                authorizationDescriptionKey: "onboarding_authorization_google_description",
                systemImage: "globe"
            )
        }
    }
}

enum PreferencesTab: CaseIterable, Hashable {
    case general
    case calendars
    case meetingOpening
    case menuBar
    case menuBuilder
    case notifications
    case advanced

    static let defaultSelection: PreferencesTab = .general

    // This metadata is the single source of truth for sidebar labels, icons,
    // identity, and ordering.
    var titleKey: String {
        switch self {
        case .general:
            "preferences_tab_general"
        case .calendars:
            "preferences_tab_calendars"
        case .meetingOpening:
            "preferences_tab_meeting_opening"
        case .menuBar:
            "preferences_tab_menu_bar"
        case .menuBuilder:
            "preferences_tab_menu_builder"
        case .notifications:
            "preferences_tab_notifications"
        case .advanced:
            "preferences_tab_advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .calendars:
            "calendar"
        case .meetingOpening:
            "arrow.up.right.square"
        case .menuBar:
            "menubar.rectangle"
        case .menuBuilder:
            "slider.horizontal.below.rectangle"
        case .notifications:
            "bell"
        case .advanced:
            "slider.horizontal.3"
        }
    }

}

enum PreferencesSidebarSection: CaseIterable {
    case setup
    case experience
    case advanced

    var titleKey: String {
        switch self {
        case .setup:
            "preferences_sidebar_setup"
        case .experience:
            "preferences_sidebar_experience"
        case .advanced:
            "preferences_sidebar_advanced"
        }
    }

    var tabs: [PreferencesTab] {
        switch self {
        case .setup:
            [.general, .calendars, .meetingOpening]
        case .experience:
            [.menuBar, .menuBuilder, .notifications]
        case .advanced:
            [.advanced]
        }
    }
}

enum PreferencesStatusBarTimeOption: CaseIterable, Equatable {
    case show
    case showUnderTitle
    case hide

    var format: EventTimeFormat {
        switch self {
        case .show:
            .show
        case .showUnderTitle:
            .show_under_title
        case .hide:
            .hide
        }
    }

    var titleKey: String {
        switch self {
        case .show:
            "preferences_appearance_status_bar_time_show_value"
        case .showUnderTitle:
            "preferences_appearance_status_bar_time_show_under_title_value"
        case .hide:
            "preferences_appearance_status_bar_time_hide_value"
        }
    }
}

enum PreferencesStatusTone: Equatable {
    case neutral
    case success
    case warning
    case error
}

enum PreferencesProviderConnectionState: Equatable {
    case initializing
    case connected
    case authRequired
    case permissionRequired
    case stale
    case error
}

struct PreferencesCalendarPresentation: Equatable {
    let activeProvider: EventStoreProvider
    let connectionState: PreferencesProviderConnectionState
    let statusTone: PreferencesStatusTone
    let selectedCalendarCount: Int
    let availableCalendarCount: Int
    let canReconnect: Bool
    let canRequestAccess: Bool
    let canOpenCalendarSettings: Bool
    let providerTitleKey: String
    let providerDataSourceKey: String
    let providerAccountScopeKey: String
    let statusTextKey: String
    let emptyStateTextKey: String
    /// Newest event `lastModifiedDate` from the last successful fetch, carried
    /// over from `ProviderHealth.lastSyncedChange`. `nil` when there are no
    /// events / no modification dates — the Calendars tab hides the line then.
    /// The user eyeballs this for staleness; it is surfaced, never auto-judged.
    let lastSyncedChange: Date?
    /// Offer the "Re-authenticate Account…" affordance (System Settings ▸
    /// Internet Accounts). EventKit-only: that is where the underlying
    /// CalDAV/Google/Exchange accounts whose expired credentials cause silent
    /// stale data are re-signed-in.
    let canReauthenticateAccount: Bool

    /// - Parameter authorizationStatus: the live EventKit calendar
    ///   authorization (from `PermissionReporter.calendarAuthorizationStatus()`).
    ///   Passed in rather than read here so `make` stays pure/testable. Defaults
    ///   to `.authorized` so it does not surface a "Grant Access" affordance for
    ///   non-EventKit providers or call sites that predate the parameter.
    static func make(
        from state: AppState,
        authorizationStatus: PermissionSnapshot.CalendarAccess = .authorized
    ) -> PreferencesCalendarPresentation {
        let connectionState: PreferencesProviderConnectionState
        var statusTone: PreferencesStatusTone
        var statusTextKey: String

        if state.providerHealth.authRequired {
            connectionState = .authRequired
            statusTone = .error
            statusTextKey = "preferences_status_state_auth_required"
        } else if state.activeProvider == .macOSEventKit,
                  state.providerHealth.lastErrorDescription != nil,
                  state.providerHealth.lastSuccessfulRefresh == nil {
            connectionState = .permissionRequired
            statusTone = .error
            statusTextKey = "preferences_status_state_permission_required"
        } else if state.providerHealth.isStale {
            connectionState = .stale
            statusTone = .warning
            statusTextKey = "preferences_status_state_stale"
        } else if state.providerHealth.lastErrorDescription != nil {
            connectionState = .error
            statusTone = .error
            statusTextKey = "preferences_status_state_error"
        } else if state.providerHealth.lastSuccessfulRefresh != nil {
            connectionState = .connected
            statusTone = .success
            statusTextKey = "preferences_status_state_ok"
        } else {
            connectionState = .initializing
            statusTone = .neutral
            statusTextKey = "preferences_status_state_initializing"
        }

        let availableCalendarCount = state.calendars.count

        // The provider refreshed successfully but exposes zero calendars (no
        // calendar accounts / data sources synced on this Mac). That is not
        // "Up to date" — report it honestly so the user knows to connect an
        // account, and keep the Calendar-settings shortcut available.
        let connectedWithoutCalendars = connectionState == .connected
            && availableCalendarCount == 0
        if connectedWithoutCalendars {
            statusTone = .warning
            statusTextKey = "preferences_status_state_no_calendars"
        }

        let calendarSource = CalendarSourcePresentation.make(for: state.activeProvider)

        let emptyStateTextKey = switch connectionState {
        case .authRequired:
            "onboarding_calendar_selection_reconnect"
        case .permissionRequired:
            "onboarding_calendar_selection_permission"
        case .initializing, .connected, .stale, .error:
            connectedWithoutCalendars
                ? "preferences_calendars_empty_no_accounts"
                : "onboarding_calendar_selection_empty"
        }

        let availableIDs = Set(state.calendars.map(\.id))
        let selectedCalendarCount = state.selectedCalendarIDs.filter {
            availableIDs.contains($0)
        }.count

        // EventKit is the only provider that can be in `.notDetermined`: a
        // normal post-onboarding launch never runs the provider switch that
        // prompts, so the app can silently hold no calendar access. Surface an
        // explicit "Grant Calendar Access" affordance in that state. Once the
        // status is `.denied`/`.restricted` a request no longer prompts, so we
        // fall back to the Calendar-settings shortcut instead — hence
        // `canOpenCalendarSettings` is suppressed while a request can still
        // prompt (`.notDetermined`).
        let canRequestAccess = state.activeProvider == .macOSEventKit
            && authorizationStatus == .notDetermined

        return PreferencesCalendarPresentation(
            activeProvider: state.activeProvider,
            connectionState: connectionState,
            statusTone: statusTone,
            selectedCalendarCount: selectedCalendarCount,
            availableCalendarCount: availableCalendarCount,
            canReconnect: state.activeProvider == .googleCalendar
                && connectionState == .authRequired,
            canRequestAccess: canRequestAccess,
            canOpenCalendarSettings: state.activeProvider == .macOSEventKit
                && !canRequestAccess
                && (connectionState == .permissionRequired || connectedWithoutCalendars),
            providerTitleKey: calendarSource.titleKey,
            providerDataSourceKey: calendarSource.dataSourceKey,
            providerAccountScopeKey: calendarSource.accountScopeKey,
            statusTextKey: statusTextKey,
            emptyStateTextKey: emptyStateTextKey,
            lastSyncedChange: state.providerHealth.lastSyncedChange,
            canReauthenticateAccount: state.activeProvider == .macOSEventKit
        )
    }
}

enum ProviderPickerSelectionPolicy {
    static func synchronizedSelection(
        currentSelection: EventStoreProvider,
        activeProvider: EventStoreProvider,
        providerChangeInProgress: Bool
    ) -> EventStoreProvider {
        providerChangeInProgress ? currentSelection : activeProvider
    }

    static func shouldRequestChange(
        selectedProvider: EventStoreProvider,
        activeProvider: EventStoreProvider,
        providerChangeInProgress: Bool
    ) -> Bool {
        selectedProvider != activeProvider && !providerChangeInProgress
    }
}

enum BrowserPickerOptions {
    static func make(
        configured: [Browser],
        selected: Browser,
        systemDefault: Browser = systemDefaultBrowser
    ) -> [Browser] {
        var options = [systemDefault]
        for browser in configured where !options.contains(browser) {
            options.append(browser)
        }
        if !options.contains(selected) {
            options.append(selected)
        }
        return options
    }
}

struct RegexEditDraft: Equatable, Identifiable {
    let originalValue: String?
    var value: String

    /// Identity for `.sheet(item:)` presentation. `nil` originalValue (an add)
    /// gets a distinct id from any edit so the editor rebuilds with the right
    /// seed value each time it is presented.
    var id: String { originalValue ?? "" }

    static func adding() -> RegexEditDraft {
        RegexEditDraft(originalValue: nil, value: "")
    }

    static func editing(_ regex: String) -> RegexEditDraft {
        RegexEditDraft(originalValue: regex, value: regex)
    }
}

enum RegexListSaveResult: Equatable {
    case saved([String])
    case duplicate
    case originalMissing
}

enum RegexListEditingPolicy {
    static func saving(
        _ draft: RegexEditDraft,
        in regexes: [String]
    ) -> RegexListSaveResult {
        if let originalValue = draft.originalValue {
            guard let index = regexes.firstIndex(of: originalValue) else {
                return .originalMissing
            }
            guard draft.value == originalValue || !regexes.contains(draft.value) else {
                return .duplicate
            }

            var updated = regexes
            updated[index] = draft.value
            return .saved(updated)
        }

        guard !regexes.contains(draft.value) else {
            return .duplicate
        }
        return .saved(regexes + [draft.value])
    }
}

enum MeetingProviderBrowserSelection {
    static func selectedBrowser(
        providerID: String,
        providerBrowsers: [String: Browser]
    ) -> Browser {
        providerBrowsers[providerID] ?? systemDefaultBrowser
    }

    static func updating(
        providerID: String,
        browser: Browser,
        providerBrowsers: [String: Browser]
    ) -> [String: Browser] {
        var updated = providerBrowsers
        if browser == systemDefaultBrowser {
            updated.removeValue(forKey: providerID)
        } else {
            updated[providerID] = browser
        }
        return updated
    }
}

enum MeetingProviderOpeningSelection: Hashable {
    case browser(Browser)
    case mode(MeetingOpeningMode)
}

struct MeetingProviderOpeningPreferences: Equatable {
    let providerBrowsers: [String: Browser]
    let providerOpeningModes: [String: String]
}

enum MeetingProviderOpeningSelectionPolicy {
    static func selected(
        provider: MeetingProvider,
        providerBrowsers: [String: Browser],
        providerOpeningModes: [String: String]
    ) -> MeetingProviderOpeningSelection {
        if let modeID = providerOpeningModes[provider.id],
           let mode = MeetingOpeningMode(rawValue: modeID),
           provider.openingModes.contains(mode) {
            return .mode(mode)
        }
        if let browser = providerBrowsers[provider.id] {
            if let mode = legacyOpeningMode(for: provider, browser: browser) {
                return .mode(mode)
            }
            return .browser(browser)
        }
        return .browser(systemDefaultBrowser)
    }

    static func updating(
        provider: MeetingProvider,
        selection: MeetingProviderOpeningSelection,
        providerBrowsers: [String: Browser],
        providerOpeningModes: [String: String]
    ) -> MeetingProviderOpeningPreferences {
        var browsers = providerBrowsers
        var modes = providerOpeningModes

        switch selection {
        case .browser(let browser):
            modes.removeValue(forKey: provider.id)
            if browser == systemDefaultBrowser {
                browsers.removeValue(forKey: provider.id)
            } else {
                browsers[provider.id] = browser
            }
        case .mode(let mode):
            guard provider.openingModes.contains(mode) else {
                modes.removeValue(forKey: provider.id)
                return MeetingProviderOpeningPreferences(
                    providerBrowsers: browsers,
                    providerOpeningModes: modes
                )
            }
            modes[provider.id] = mode.rawValue
            if let browser = browsers[provider.id],
               legacyOpeningMode(for: provider, browser: browser) != nil {
                browsers.removeValue(forKey: provider.id)
            }
        }

        return MeetingProviderOpeningPreferences(
            providerBrowsers: browsers,
            providerOpeningModes: modes
        )
    }
}
