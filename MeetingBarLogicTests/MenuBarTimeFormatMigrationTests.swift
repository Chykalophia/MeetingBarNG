//
//  MenuBarTimeFormatMigrationTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for the one-time migration that retires the "Time next to the
//  title" control (`eventTimeFormat`) without dropping anybody's setting:
//
//    • `.show` / `.hide` become the presence or absence of a Countdown block.
//    • `.show_under_title` becomes "Two lines" on the Menu Bar pane.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import XCTest

@testable import MeetingBarLogic

final class MenuBarTimeFormatMigrationTests: XCTestCase {
    // MARK: - Never composed before: seed from what they were seeing

    func testSeedsTheLegacyArrangementWhenNothingIsStored() {
        let plan = MenuBarTimeFormatMigration.plan(
            storedTokens: [],
            legacyTokens: ["icon", "title", "countdown"],
            timeUnderTitle: false
        )
        XCTAssertEqual(plan.tokens, ["icon", "title", "countdown"])
        XCTAssertEqual(plan.twoLines, false)
    }

    func testUnderTitleBecomesTwoLines() {
        let plan = MenuBarTimeFormatMigration.plan(
            storedTokens: [],
            legacyTokens: ["icon", "title", "countdown"],
            timeUnderTitle: true
        )
        XCTAssertEqual(plan.twoLines, true)
    }

    func testHiddenTimeSeedsNoCountdownBlock() {
        // `.hide` derives a legacy list without a countdown; the migration must
        // not add one back, or the menu bar gains a countdown nobody asked for.
        let plan = MenuBarTimeFormatMigration.plan(
            storedTokens: [],
            legacyTokens: ["icon", "title"],
            timeUnderTitle: false
        )
        XCTAssertEqual(plan.tokens, ["icon", "title"])
        XCTAssertEqual(plan.twoLines, false)
    }

    func testStoredGarbageCountsAsNothingStored() {
        let plan = MenuBarTimeFormatMigration.plan(
            storedTokens: ["nonsense"],
            legacyTokens: ["icon", "title"],
            timeUnderTitle: false
        )
        XCTAssertEqual(plan.tokens, ["icon", "title"])
    }

    // MARK: - Already composed: leave them alone

    func testAnExistingArrangementIsNeverRewritten() {
        let plan = MenuBarTimeFormatMigration.plan(
            storedTokens: ["clock", "date"],
            legacyTokens: ["icon", "title", "countdown"],
            timeUnderTitle: true
        )
        XCTAssertNil(plan.tokens, "the user's own arrangement must survive the migration untouched")
        XCTAssertNil(
            plan.twoLines,
            "`eventTimeFormat` was inert for anyone already composing, so applying it now would "
                + "change a menu bar they never saw it affect"
        )
    }

    func testNoChangeIsTheEmptyPlan() {
        XCTAssertNil(MenuBarTimeFormatMigrationPlan.noChange.tokens)
        XCTAssertNil(MenuBarTimeFormatMigrationPlan.noChange.twoLines)
    }
}
