//
//  TimeFormatDefaultMigrationTests.swift
//  MeetingBarTests
//
//  MeetingBarNG defaults new installs to 12-hour; the migration pins existing
//  installs (that never chose a format) to their prior 24-hour so upgraders are
//  never silently flipped. The decision is tested as pure logic.
//

import XCTest

@testable import MeetingBar

final class TimeFormatDefaultMigrationTests: XCTestCase {
    func testUpgraderWithNoExplicitChoiceIsPinnedTo24Hour() {
        XCTAssertTrue(
            TimeFormatDefaultMigration.shouldPinToMilitary(
                onboardingCompleted: true, hasStoredTimeFormat: false
            )
        )
    }

    func testUpgraderWithExplicitChoiceIsNotPinned() {
        XCTAssertFalse(
            TimeFormatDefaultMigration.shouldPinToMilitary(
                onboardingCompleted: true, hasStoredTimeFormat: true
            )
        )
    }

    func testNewInstallIsNotPinned() {
        XCTAssertFalse(
            TimeFormatDefaultMigration.shouldPinToMilitary(
                onboardingCompleted: false, hasStoredTimeFormat: false
            )
        )
    }

    func testNewInstallWithStoredValueIsNotPinned() {
        XCTAssertFalse(
            TimeFormatDefaultMigration.shouldPinToMilitary(
                onboardingCompleted: false, hasStoredTimeFormat: true
            )
        )
    }
}
