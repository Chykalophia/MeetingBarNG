//
//  PreferencesPresentationTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBarNG

final class PreferencesPresentationTests: XCTestCase {
    func testCalendarSourcesExplainDistinctDataSourcesAndAccountScopes() {
        // Option A ships the macOS Calendar provider only; `make(for:)` still
        // supports Google for any install left on the provider from a prior build.
        XCTAssertEqual(
            CalendarSourcePresentation.all.map(\.provider),
            [.macOSEventKit]
        )

        let macOSSource = CalendarSourcePresentation.make(for: .macOSEventKit)
        XCTAssertEqual(macOSSource.titleKey, "onboarding_apple_calendar_title")
        XCTAssertEqual(
            macOSSource.dataSourceKey,
            "access_screen_provider_macos_data_source"
        )
        XCTAssertEqual(
            macOSSource.accountScopeKey,
            "access_screen_provider_macos_number_of_accounts"
        )

        let googleSource = CalendarSourcePresentation.make(for: .googleCalendar)
        XCTAssertEqual(googleSource.titleKey, "onboarding_google_calendar_title")
        XCTAssertEqual(
            googleSource.dataSourceKey,
            "access_screen_provider_gcalendar_data_source"
        )
        XCTAssertEqual(
            googleSource.accountScopeKey,
            "access_screen_provider_gcalendar_number_of_accounts"
        )
    }

    /// Pins the Phase 2 IA. `Display`, `Events` and `Advanced` are gone as panes:
    /// in a calendar app every setting displays events, so "Display" and "Events"
    /// could not be told apart, and "Advanced" is a category defined by developer
    /// anxiety that accretes forever. Sidebar order is the order of the routing
    /// rule — where meetings come from, which ones exist, then each surface that
    /// draws them, then what happens when you act, then the app itself.
    func testPreferencesTabsExposeCoreProductConceptsInOrder() {
        XCTAssertEqual(
            PreferencesTab.allCases,
            [
                .calendars,
                .filters,
                .menuBar,
                .dropdown,
                .calendarWindow,
                .joining,
                .alerts,
                .general
            ]
        )
        XCTAssertEqual(
            PreferencesTab.allCases.map(\.titleKey),
            [
                "preferences_tab_calendars",
                "preferences_tab_filters",
                "preferences_tab_menu_bar",
                "preferences_tab_dropdown",
                "preferences_tab_calendar_window",
                "preferences_tab_joining",
                "preferences_tab_alerts",
                "preferences_tab_general"
            ]
        )
        XCTAssertEqual(
            PreferencesTab.allCases.map(\.systemImage),
            [
                "calendar",
                "line.3.horizontal.decrease.circle",
                "menubar.rectangle",
                "rectangle.grid.1x2",
                "rectangle.on.rectangle",
                "video",
                "bell",
                "gearshape"
            ]
        )
    }

    /// Opening Preferences lands on where meetings come from, never on credits —
    /// and never on a pane whose name means "miscellaneous".
    func testPreferencesDefaultSelectionIsCalendars() {
        XCTAssertEqual(PreferencesTab.defaultSelection, .calendars)
    }

    /// Every pane states its own purpose. Eight panes are only holdable if each
    /// one says what it is for, so a missing purpose line is a test failure and
    /// not a cosmetic omission.
    func testEveryPaneDeclaresADistinctPurpose() {
        let purposeKeys = PreferencesTab.allCases.map(\.purposeKey)
        XCTAssertEqual(Set(purposeKeys).count, PreferencesTab.allCases.count)
        for key in purposeKeys {
            XCTAssertFalse(key.isEmpty)
        }
    }

    // `testStatusBarTimeOptionsIncludeHide` is gone with
    // `PreferencesStatusBarTimeOption`: the "Time next to the title" picker it
    // fed is deleted. Showing the time is now the presence of the Countdown
    // block on the Menu Bar pane, show-under-title is that pane's One line /
    // Two lines control, and `MenuBarTimeFormatMigration` (tested hostlessly)
    // carries a stored `eventTimeFormat` across to both.

    func testConnectedProviderPresentationUsesAppStateCounts() {
        let refreshedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var state = AppState()
        state.activeProvider = .googleCalendar
        state.calendars = [
            makeFakeCalendar(id: "work"),
            makeFakeCalendar(id: "personal")
        ]
        state.selectedCalendarIDs = ["work"]
        state.providerHealth = ProviderHealth.success(attempted: refreshedAt)

        let presentation = PreferencesCalendarPresentation.make(from: state)

        XCTAssertEqual(presentation.connectionState, .connected)
        XCTAssertEqual(presentation.statusTone, .success)
        XCTAssertEqual(presentation.statusTextKey, "preferences_calendars_status_ok")
        XCTAssertEqual(presentation.providerTitleKey, "onboarding_google_calendar_title")
        XCTAssertEqual(
            presentation.providerDataSourceKey,
            "access_screen_provider_gcalendar_data_source"
        )
        XCTAssertEqual(
            presentation.providerAccountScopeKey,
            "access_screen_provider_gcalendar_number_of_accounts"
        )
        XCTAssertEqual(presentation.selectedCalendarCount, 1)
        XCTAssertEqual(presentation.availableCalendarCount, 2)
        XCTAssertFalse(presentation.canReconnect)
    }

    func testConnectedProviderWithoutCalendarsReportsNoCalendars() {
        // Refresh succeeded but the provider exposes zero calendars: surface a
        // warning ("No calendars found") instead of "Up to date", and keep the
        // Calendar-settings shortcut so the user can connect an account.
        let refreshedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var state = AppState()
        state.activeProvider = .macOSEventKit
        state.calendars = []
        state.selectedCalendarIDs = ["stale"]
        state.providerHealth = ProviderHealth.success(attempted: refreshedAt)

        let presentation = PreferencesCalendarPresentation.make(from: state)

        XCTAssertEqual(presentation.connectionState, .connected)
        XCTAssertEqual(presentation.statusTone, .warning)
        XCTAssertEqual(
            presentation.statusTextKey,
            "preferences_calendars_status_no_calendars"
        )
        XCTAssertEqual(presentation.availableCalendarCount, 0)
        XCTAssertEqual(presentation.selectedCalendarCount, 0)
        XCTAssertTrue(presentation.canOpenCalendarSettings)
        XCTAssertEqual(
            presentation.emptyStateTextKey,
            "preferences_calendars_empty_no_accounts"
        )
    }

    func testNotDeterminedEventKitOffersGrantAccessAndHidesSettings() {
        // Fresh post-onboarding launch: macOS EventKit is active but access is
        // still undetermined. Offer the "Grant Calendar Access" affordance and
        // suppress the Calendar-settings shortcut (a request still prompts).
        var state = AppState()
        state.activeProvider = .macOSEventKit
        state.calendars = []

        let presentation = PreferencesCalendarPresentation.make(
            from: state,
            authorizationStatus: .notDetermined
        )

        XCTAssertTrue(presentation.canRequestAccess)
        XCTAssertFalse(presentation.canOpenCalendarSettings)
        XCTAssertFalse(presentation.canReconnect)
    }

    func testNotDeterminedEventKitKeepsGrantAccessEvenAfterPermissionError() {
        // A denied/aborted first prompt records an error → permissionRequired.
        // While the OS still reports `.notDetermined`, keep offering Grant
        // Access rather than the Calendar-settings shortcut.
        var state = AppState()
        state.activeProvider = .macOSEventKit
        state.calendars = []
        state.providerHealth = ProviderHealth(
            lastAttemptedRefresh: Date(timeIntervalSince1970: 1_700_000_000),
            lastErrorDescription: "Access denied",
            isStale: true
        )

        let presentation = PreferencesCalendarPresentation.make(
            from: state,
            authorizationStatus: .notDetermined
        )

        XCTAssertEqual(presentation.connectionState, .permissionRequired)
        XCTAssertTrue(presentation.canRequestAccess)
        XCTAssertFalse(presentation.canOpenCalendarSettings)
    }

    func testDeniedEventKitOffersOpenSettingsNotGrantAccess() {
        // Once denied, a request no longer prompts: hide Grant Access and fall
        // back to the Calendar-settings shortcut.
        var state = AppState()
        state.activeProvider = .macOSEventKit
        state.calendars = [makeFakeCalendar(id: "cached")]
        state.providerHealth = ProviderHealth(
            lastAttemptedRefresh: Date(timeIntervalSince1970: 1_700_000_000),
            lastErrorDescription: "Access denied",
            isStale: true
        )

        let presentation = PreferencesCalendarPresentation.make(
            from: state,
            authorizationStatus: .denied
        )

        XCTAssertEqual(presentation.connectionState, .permissionRequired)
        XCTAssertFalse(presentation.canRequestAccess)
        XCTAssertTrue(presentation.canOpenCalendarSettings)
    }

    func testAuthorizedEventKitDoesNotOfferGrantAccess() {
        // Access granted with calendars present: no Grant Access, no settings
        // shortcut — the connected happy path is unchanged.
        let refreshedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var state = AppState()
        state.activeProvider = .macOSEventKit
        state.calendars = [makeFakeCalendar(id: "work")]
        state.selectedCalendarIDs = ["work"]
        state.providerHealth = ProviderHealth.success(attempted: refreshedAt)

        let presentation = PreferencesCalendarPresentation.make(
            from: state,
            authorizationStatus: .authorized
        )

        XCTAssertFalse(presentation.canRequestAccess)
        XCTAssertFalse(presentation.canOpenCalendarSettings)
    }

    func testAuthorizedEventKitWithoutCalendarsKeepsSettingsNotGrantAccess() {
        // Granted but empty: keep the Calendar-settings shortcut (and Refresh),
        // never Grant Access.
        let refreshedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var state = AppState()
        state.activeProvider = .macOSEventKit
        state.calendars = []
        state.providerHealth = ProviderHealth.success(attempted: refreshedAt)

        let presentation = PreferencesCalendarPresentation.make(
            from: state,
            authorizationStatus: .authorized
        )

        XCTAssertFalse(presentation.canRequestAccess)
        XCTAssertTrue(presentation.canOpenCalendarSettings)
        XCTAssertEqual(
            presentation.statusTextKey,
            "preferences_calendars_status_no_calendars"
        )
    }

    func testGoogleProviderNeverOffersGrantAccess() {
        // Grant Access is EventKit-only, even if a status is somehow undetermined.
        var state = AppState()
        state.activeProvider = .googleCalendar
        state.calendars = []

        let presentation = PreferencesCalendarPresentation.make(
            from: state,
            authorizationStatus: .notDetermined
        )

        XCTAssertFalse(presentation.canRequestAccess)
    }

    func testGoogleAuthRequiredPresentationOffersReconnect() {
        var state = AppState()
        state.activeProvider = .googleCalendar
        state.calendars = [makeFakeCalendar(id: "cached")]
        state.providerHealth = ProviderHealth(
            lastErrorDescription: "Sign in again",
            isStale: true,
            authRequired: true
        )

        let presentation = PreferencesCalendarPresentation.make(from: state)

        XCTAssertEqual(presentation.connectionState, .authRequired)
        XCTAssertEqual(presentation.statusTone, .error)
        XCTAssertTrue(presentation.canReconnect)
        XCTAssertFalse(presentation.canOpenCalendarSettings)
        XCTAssertEqual(
            presentation.emptyStateTextKey,
            "onboarding_calendar_selection_reconnect"
        )
    }

    func testInitialEventKitFailureIsPresentedAsPermissionRequired() {
        var state = AppState()
        state.activeProvider = .macOSEventKit
        state.calendars = [makeFakeCalendar(id: "cached")]
        state.providerHealth = ProviderHealth(
            lastAttemptedRefresh: Date(timeIntervalSince1970: 1_700_000_000),
            lastErrorDescription: "Access denied",
            isStale: true
        )

        let presentation = PreferencesCalendarPresentation.make(from: state)

        XCTAssertEqual(presentation.connectionState, .permissionRequired)
        XCTAssertEqual(
            presentation.statusTextKey,
            "preferences_calendars_status_permission_required"
        )
        XCTAssertTrue(presentation.canOpenCalendarSettings)
        XCTAssertFalse(presentation.canReconnect)
    }

    func testFailedRefreshWithCachedDataIsPresentedAsStale() {
        let refreshedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var state = AppState()
        state.activeProvider = .googleCalendar
        state.providerHealth = ProviderHealth(
            lastSuccessfulRefresh: refreshedAt,
            lastAttemptedRefresh: refreshedAt.addingTimeInterval(60),
            lastErrorDescription: "Network unavailable",
            isStale: true
        )

        let presentation = PreferencesCalendarPresentation.make(from: state)

        XCTAssertEqual(presentation.connectionState, .stale)
        XCTAssertEqual(presentation.statusTone, .warning)
        XCTAssertEqual(presentation.statusTextKey, "preferences_calendars_status_stale")
    }

    func testPresentationCarriesNewestSyncedChangeFromProviderHealth() {
        // The "most recent calendar change" staleness signal flows from
        // ProviderHealth.lastSyncedChange straight onto the presentation.
        let refreshedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let newestChange = Date(timeIntervalSince1970: 1_699_000_000)
        var state = AppState()
        state.activeProvider = .macOSEventKit
        state.calendars = [makeFakeCalendar(id: "work")]
        state.selectedCalendarIDs = ["work"]
        state.providerHealth = ProviderHealth.success(
            attempted: refreshedAt,
            lastSyncedChange: newestChange
        )

        let presentation = PreferencesCalendarPresentation.make(
            from: state,
            authorizationStatus: .authorized
        )

        XCTAssertEqual(presentation.lastSyncedChange, newestChange)
    }

    func testPresentationHasNoSyncedChangeWhenProviderHealthLacksOne() {
        // No event carried a modification date: the tab hides the line, so the
        // presentation must expose nil rather than fabricate a timestamp.
        let refreshedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var state = AppState()
        state.activeProvider = .macOSEventKit
        state.calendars = [makeFakeCalendar(id: "work")]
        state.providerHealth = ProviderHealth.success(attempted: refreshedAt)

        let presentation = PreferencesCalendarPresentation.make(from: state)

        XCTAssertNil(presentation.lastSyncedChange)
    }

    func testEventKitOffersReauthenticateAccountAffordance() {
        // The "Re-authenticate Account…" fix-path (System Settings ▸ Internet
        // Accounts) is offered for macOS EventKit, the provider whose underlying
        // accounts can hold expired credentials that stall sync silently.
        var state = AppState()
        state.activeProvider = .macOSEventKit

        let presentation = PreferencesCalendarPresentation.make(from: state)

        XCTAssertTrue(presentation.canReauthenticateAccount)
    }

    func testGoogleProviderDoesNotOfferReauthenticateAccountAffordance() {
        // The native Google provider has its own Reconnect flow; the Internet
        // Accounts affordance is EventKit-only.
        var state = AppState()
        state.activeProvider = .googleCalendar

        let presentation = PreferencesCalendarPresentation.make(from: state)

        XCTAssertFalse(presentation.canReauthenticateAccount)
    }

    func testBrowserPickerAlwaysIncludesStoredSelection() {
        let safari = Browser(
            name: "Safari",
            path: "/Applications/Safari.app"
        )
        let removedCustomBrowser = Browser(
            name: "Work Chrome",
            path: "/Applications/Google Chrome.app"
        )

        let options = BrowserPickerOptions.make(
            configured: [safari],
            selected: removedCustomBrowser
        )

        XCTAssertEqual(options.first, systemDefaultBrowser)
        XCTAssertTrue(options.contains(safari))
        XCTAssertTrue(options.contains(removedCustomBrowser))
    }

    func testBrowserPickerDoesNotDuplicateSystemOrConfiguredBrowser() {
        let safari = Browser(
            name: "Safari",
            path: "/Applications/Safari.app"
        )

        XCTAssertEqual(
            BrowserPickerOptions.make(
                configured: [systemDefaultBrowser, safari, safari],
                selected: safari
            ),
            [systemDefaultBrowser, safari]
        )
    }

    func testRegexDraftDoesNotMutateOriginalListBeforeSave() {
        let regexes = ["meet\\.google\\.com", "zoom\\.us"]

        let draft = RegexEditDraft.editing(regexes[0])

        XCTAssertEqual(draft.originalValue, regexes[0])
        XCTAssertEqual(draft.value, regexes[0])
        XCTAssertEqual(regexes, ["meet\\.google\\.com", "zoom\\.us"])
    }

    func testSavingRegexDraftReplacesOriginalInPlace() {
        var draft = RegexEditDraft.editing("meet\\.google\\.com")
        draft.value = "teams\\.microsoft\\.com"

        XCTAssertEqual(
            RegexListEditingPolicy.saving(
                draft,
                in: ["meet\\.google\\.com", "zoom\\.us"]
            ),
            .saved(["teams\\.microsoft\\.com", "zoom\\.us"])
        )
    }

    func testSavingRegexDraftPreventsDuplicates() {
        var draft = RegexEditDraft.editing("meet\\.google\\.com")
        draft.value = "zoom\\.us"

        XCTAssertEqual(
            RegexListEditingPolicy.saving(
                draft,
                in: ["meet\\.google\\.com", "zoom\\.us"]
            ),
            .duplicate
        )
    }

    func testSavingNewRegexAppendsWithoutChangingExistingValues() {
        var draft = RegexEditDraft.adding()
        draft.value = "teams\\.microsoft\\.com"

        XCTAssertEqual(
            RegexListEditingPolicy.saving(draft, in: ["zoom\\.us"]),
            .saved(["zoom\\.us", "teams\\.microsoft\\.com"])
        )
    }

    func testMeetingProviderOpeningSelectionRestoresLegacySentinel() {
        let provider = MeetingProvider.provider(for: .zoom)!

        XCTAssertEqual(
            MeetingProviderOpeningSelectionPolicy.selected(
                provider: provider,
                providerBrowsers: [provider.id: zoomAppBrowser],
                providerOpeningModes: [:]
            ),
            .mode(.zoomApp)
        )
    }

    func testMeetingProviderOpeningSelectionPersistsModeAndBrowserFallback() {
        let provider = MeetingProvider.provider(for: .zoom)!
        let chrome = Browser(
            name: "Google Chrome",
            path: "/Applications/Google Chrome.app"
        )

        let updated = MeetingProviderOpeningSelectionPolicy.updating(
            provider: provider,
            selection: .mode(.zoomWebApp),
            providerBrowsers: [provider.id: chrome],
            providerOpeningModes: [:]
        )

        XCTAssertEqual(updated.providerBrowsers[provider.id], chrome)
        XCTAssertEqual(
            updated.providerOpeningModes[provider.id],
            MeetingOpeningMode.zoomWebApp.rawValue
        )
        XCTAssertEqual(
            MeetingProviderOpeningSelectionPolicy.selected(
                provider: provider,
                providerBrowsers: updated.providerBrowsers,
                providerOpeningModes: updated.providerOpeningModes
            ),
            .mode(.zoomWebApp)
        )
    }

    func testMeetingProviderOpeningSelectionReplacesLegacySentinelWithMode() {
        let provider = MeetingProvider.provider(for: .meet)!

        let updated = MeetingProviderOpeningSelectionPolicy.updating(
            provider: provider,
            selection: .mode(.googleMeetPWA),
            providerBrowsers: [provider.id: meetInOneBrowser],
            providerOpeningModes: [:]
        )

        XCTAssertNil(updated.providerBrowsers[provider.id])
        XCTAssertEqual(
            updated.providerOpeningModes[provider.id],
            MeetingOpeningMode.googleMeetPWA.rawValue
        )
    }

    func testMeetingProviderOpeningSelectionBrowserClearsMode() {
        let provider = MeetingProvider.provider(for: .facebook_workspace)!
        let safari = Browser(
            name: "Safari",
            path: "/Applications/Safari.app"
        )

        let updated = MeetingProviderOpeningSelectionPolicy.updating(
            provider: provider,
            selection: .browser(safari),
            providerBrowsers: [:],
            providerOpeningModes: [
                provider.id: MeetingOpeningMode.workplaceApp.rawValue
            ]
        )

        XCTAssertEqual(updated.providerBrowsers[provider.id], safari)
        XCTAssertNil(updated.providerOpeningModes[provider.id])
    }

    func testMeetingProviderOpeningSelectionDefaultClearsOverrides() {
        let provider = MeetingProvider.provider(for: .zoom)!

        let updated = MeetingProviderOpeningSelectionPolicy.updating(
            provider: provider,
            selection: .browser(systemDefaultBrowser),
            providerBrowsers: [provider.id: zoomAppBrowser],
            providerOpeningModes: [
                provider.id: MeetingOpeningMode.zoomWebApp.rawValue
            ]
        )

        XCTAssertNil(updated.providerBrowsers[provider.id])
        XCTAssertNil(updated.providerOpeningModes[provider.id])
    }

    func testMeetingProviderOpeningSelectionIgnoresUnknownStoredMode() {
        let provider = MeetingProvider.provider(for: .zoom)!
        let chrome = Browser(
            name: "Google Chrome",
            path: "/Applications/Google Chrome.app"
        )

        XCTAssertEqual(
            MeetingProviderOpeningSelectionPolicy.selected(
                provider: provider,
                providerBrowsers: [provider.id: chrome],
                providerOpeningModes: [provider.id: "removed-mode"]
            ),
            .browser(chrome)
        )
    }
}
