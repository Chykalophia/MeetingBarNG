//
//  CalendarSourceSelectionTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for multi-source calendar connection (MeetingBarNG).
//

import XCTest

@testable import MeetingBarLogic

final class CalendarSourceSelectionTests: XCTestCase {
    // MARK: - The non-empty invariant

    func test_emptySelectionFallsBackToMacOSCalendar() {
        XCTAssertEqual(CalendarSourceSelection(enabled: []).enabled, [.macOSEventKit])
    }

    func test_disablingTheLastSourceIsRefused() {
        let selection = CalendarSourceSelection(enabled: [.googleCalendar])
        XCTAssertFalse(selection.canDisable(.googleCalendar))
        XCTAssertEqual(selection.disabling(.googleCalendar).enabled, [.googleCalendar])
    }

    func test_disablingIsAllowedWhileASecondSourceRemains() {
        let selection = CalendarSourceSelection(enabled: [.macOSEventKit, .googleCalendar])
        XCTAssertTrue(selection.canDisable(.macOSEventKit))
        XCTAssertEqual(selection.disabling(.macOSEventKit).enabled, [.googleCalendar])
    }

    // MARK: - Normalization

    func test_orderIsCanonicalRegardlessOfInputOrder() {
        let selection = CalendarSourceSelection(enabled: [.googleCalendar, .macOSEventKit])
        XCTAssertEqual(selection.enabled, [.macOSEventKit, .googleCalendar])
    }

    func test_duplicatesAreCollapsed() {
        let selection = CalendarSourceSelection(enabled: [.googleCalendar, .googleCalendar])
        XCTAssertEqual(selection.enabled, [.googleCalendar])
    }

    // MARK: - Toggling

    func test_enablingIsIdempotent() {
        let selection = CalendarSourceSelection(enabled: [.macOSEventKit])
        XCTAssertEqual(selection.enabling(.macOSEventKit), selection)
    }

    func test_bothSourcesCanBeEnabledAtOnce() {
        let selection = CalendarSourceSelection(enabled: [.macOSEventKit])
            .enabling(.googleCalendar)
        XCTAssertEqual(selection.enabled, [.macOSEventKit, .googleCalendar])
    }

    func test_settingDrivesBothDirections() {
        var selection = CalendarSourceSelection(enabled: [.macOSEventKit])
        selection = selection.setting(.googleCalendar, enabled: true)
        XCTAssertTrue(selection.isEnabled(.googleCalendar))
        selection = selection.setting(.googleCalendar, enabled: false)
        XCTAssertFalse(selection.isEnabled(.googleCalendar))
    }

    // MARK: - Availability filtering

    func test_unavailableSourcesAreDroppedOnRead() {
        let selection = CalendarSourceSelection(enabled: [.macOSEventKit, .googleCalendar])
            .availableOnly { $0 != .googleCalendar }
        XCTAssertEqual(selection.enabled, [.macOSEventKit])
    }

    func test_filteringEverythingAwayRestoresMacOSCalendar() {
        // A build with no Google credentials, on an install that had selected
        // Google only. Reaching no source at all is worse than the default.
        let selection = CalendarSourceSelection(enabled: [.googleCalendar])
            .availableOnly { _ in false }
        XCTAssertEqual(selection.enabled, [.macOSEventKit])
    }

    func test_filteringIsNotPersistedBackIntoTheSelection() {
        // The stored selection keeps Google, so supplying credentials later
        // restores the user's choice instead of silently having erased it.
        let stored = CalendarSourceSelection(enabled: [.macOSEventKit, .googleCalendar])
        _ = stored.availableOnly { $0 != .googleCalendar }
        XCTAssertTrue(stored.isEnabled(.googleCalendar))
    }

    // MARK: - Migration off the single-provider key

    func test_migrationKeepsExactlyTheProviderInUse() {
        XCTAssertEqual(
            CalendarSourceSelection.migrating(fromSingleProvider: .googleCalendar).enabled,
            [.googleCalendar]
        )
        XCTAssertEqual(
            CalendarSourceSelection.migrating(fromSingleProvider: .macOSEventKit).enabled,
            [.macOSEventKit]
        )
    }

    // MARK: - Writes

    func test_writeSourceIsEventKitWhenConnected() {
        let selection = CalendarSourceSelection(enabled: [.macOSEventKit, .googleCalendar])
        XCTAssertEqual(selection.writeSource, .macOSEventKit)
    }

    func test_googleOnlyHasNoWriteSource() {
        // The Google provider is read-only here, so a Google-only install must
        // hide event creation/editing rather than offer an action that fails.
        let selection = CalendarSourceSelection(enabled: [.googleCalendar])
        XCTAssertNil(selection.writeSource)
    }

    // MARK: - Deduplication precedence

    func test_googleOutranksEventKitForSurvivingCopy() {
        XCTAssertLessThan(
            CalendarSourceKind.googleCalendar.deduplicationPriority,
            CalendarSourceKind.macOSEventKit.deduplicationPriority
        )
    }

    func test_displayOrderAndDedupPrecedenceAreAllowedToDisagree() {
        // Guards the intent: macOS Calendar is listed first but loses the
        // duplicate tie-break. Someone "fixing" one to match the other would
        // silently change which copy of every shared meeting the user sees.
        XCTAssertEqual(CalendarSourceKind.displayOrder.first, .macOSEventKit)
        XCTAssertEqual(
            CalendarSourceKind.allCases.min(by: { $0.deduplicationPriority < $1.deduplicationPriority }),
            .googleCalendar
        )
    }
}
