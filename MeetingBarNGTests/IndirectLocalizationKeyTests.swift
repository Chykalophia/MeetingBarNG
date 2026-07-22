//
//  IndirectLocalizationKeyTests.swift
//  MeetingBarNGTests
//
//  Guards the localization keys the tooling structurally cannot see.
//
//  `Scripts/validate_localizations.sh` scans for the literal call shape
//  `"some_key".loco()`. `Scripts/strings-lint` additionally treats any bare
//  identifier literal as a *reference*, which is what stops it reporting false
//  orphans — but it cannot tell a key literal from any other string, so it
//  cannot use that looser set to detect keys that are MISSING.
//
//  Keys reached through a property — `presentation.statusTextKey.loco()`,
//  `option.titleKey.loco()`, `tab.purposeKey.loco()` — therefore fall in the gap
//  between the two checks. The Phase 2 strings rewrite deleted ten of them and
//  every gate stayed green; the Calendars pane shipped with the literal text
//  "preferences_status_state_ok" where its sync status should be.
//
//  This test closes that gap: it resolves every key each of those properties can
//  return, and fails if the bundle hands back the key itself.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import XCTest

@testable import MeetingBarNG

final class IndirectLocalizationKeyTests: XCTestCase {
    /// A key resolves when the bundle returns something other than the key.
    private func assertResolves(
        _ key: String,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(key.isEmpty, "\(label): empty key", file: file, line: line)
        let localized = key.loco()
        XCTAssertNotEqual(
            localized,
            key,
            "\(label): \"\(key)\" is not defined in en.lproj — it would render as the raw key",
            file: file, line: line
        )
        XCTAssertFalse(
            localized.trimmingCharacters(in: .whitespaces).isEmpty,
            "\(label): \"\(key)\" resolves to an empty string",
            file: file, line: line
        )
    }

    // MARK: - Preferences panes

    func testEveryPaneTitleAndPurposeResolves() {
        for tab in PreferencesTab.allCases {
            assertResolves(tab.titleKey, "PreferencesTab.\(tab).titleKey")
            assertResolves(tab.purposeKey, "PreferencesTab.\(tab).purposeKey")
        }
    }

    // The status-bar time options are gone: `PreferencesStatusBarTimeOption` fed
    // the deleted "Time next to the title" picker, whose two capabilities now
    // live on the Menu Bar pane as the Countdown block and One line / Two lines.

    // MARK: - Calendar source presentation

    func testEveryCalendarSourceKeyResolves() {
        for provider in [EventStoreProvider.macOSEventKit, .googleCalendar] {
            let source = CalendarSourcePresentation.make(for: provider)
            assertResolves(source.titleKey, "CalendarSource(\(provider)).titleKey")
            assertResolves(source.descriptionKey, "CalendarSource(\(provider)).descriptionKey")
            assertResolves(source.dataSourceKey, "CalendarSource(\(provider)).dataSourceKey")
            assertResolves(source.accountScopeKey, "CalendarSource(\(provider)).accountScopeKey")
            assertResolves(
                source.authorizationDescriptionKey,
                "CalendarSource(\(provider)).authorizationDescriptionKey"
            )
        }
    }

    // MARK: - Calendar sync status

    /// The regression that shipped: every reachable connection state must
    /// produce a resolvable status line and empty-state line. Driving this
    /// through `make(from:)` rather than asserting a hardcoded list means a new
    /// state cannot be added without its strings.
    func testEverySyncStatusKeyResolves() {
        for presentation in Self.allCalendarPresentations() {
            assertResolves(
                presentation.statusTextKey,
                "PreferencesCalendarPresentation(\(presentation.connectionState)).statusTextKey"
            )
            assertResolves(
                presentation.emptyStateTextKey,
                "PreferencesCalendarPresentation(\(presentation.connectionState)).emptyStateTextKey"
            )
            assertResolves(
                presentation.providerTitleKey,
                "PreferencesCalendarPresentation(\(presentation.connectionState)).providerTitleKey"
            )
            assertResolves(
                presentation.providerDataSourceKey,
                "PreferencesCalendarPresentation(\(presentation.connectionState)).providerDataSourceKey"
            )
            assertResolves(
                presentation.providerAccountScopeKey,
                "PreferencesCalendarPresentation(\(presentation.connectionState)).providerAccountScopeKey"
            )
        }
    }

    /// Every connection state `PreferencesCalendarPresentation.make` can reach,
    /// built by driving the inputs that select each branch.
    private static func allCalendarPresentations() -> [PreferencesCalendarPresentation] {
        var results: [PreferencesCalendarPresentation] = []

        // .initializing — never refreshed, no error.
        results.append(.make(from: AppState()))

        // .authRequired
        var authState = AppState()
        authState.providerHealth.authRequired = true
        results.append(.make(from: authState))

        // .permissionRequired — errored and never succeeded, on EventKit.
        var permissionState = AppState()
        permissionState.activeProvider = .macOSEventKit
        permissionState.providerHealth.lastErrorDescription = "denied"
        results.append(.make(from: permissionState))

        // .stale
        var staleState = AppState()
        staleState.providerHealth.isStale = true
        results.append(.make(from: staleState))

        // .error — errored but has succeeded before.
        var errorState = AppState()
        errorState.providerHealth.lastErrorDescription = "boom"
        errorState.providerHealth.lastSuccessfulRefresh = Date()
        results.append(.make(from: errorState))

        // .connected, but exposing zero calendars (the "no accounts" branch).
        var emptyState = AppState()
        emptyState.providerHealth.lastSuccessfulRefresh = Date()
        results.append(.make(from: emptyState))

        // .notDetermined authorization — surfaces "Grant Calendar Access".
        var notDeterminedState = AppState()
        notDeterminedState.activeProvider = .macOSEventKit
        results.append(.make(from: notDeterminedState, authorizationStatus: .notDetermined))

        return results
    }
}
