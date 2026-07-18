//
//  ChangelogTests.swift
//  MeetingBarTests
//
//  The typed release-notes model and the sub-1.0 version-reset migration.
//

import XCTest

@testable import MeetingBar

final class ChangelogTests: XCTestCase {
    func testDebutReleaseSurfacesForAFreshInstall() {
        let unseen = ReleaseNotes.releases(newerThan: "0.0.0")
        XCTAssertEqual(unseen.map(\.version), ["0.1.0"])
    }

    func testNothingSurfacesOnceAcknowledged() {
        XCTAssertTrue(ReleaseNotes.releases(newerThan: "0.1.0").isEmpty)
        // And the acknowledged release moves under "earlier releases".
        XCTAssertEqual(
            ReleaseNotes.releases(upToAndIncluding: "0.1.0").map(\.version), ["0.1.0"]
        )
    }

    func testResetMigrationTargetsInheritedUpstreamVersionsOnly() {
        XCTAssertTrue(ChangelogResetMigration.shouldReset(storedLastRevised: "5.0.0"))
        XCTAssertTrue(ChangelogResetMigration.shouldReset(storedLastRevised: "4.2.0"))
        XCTAssertTrue(ChangelogResetMigration.shouldReset(storedLastRevised: "1.0.0"))
        XCTAssertFalse(ChangelogResetMigration.shouldReset(storedLastRevised: "0.1.0"))
        XCTAssertFalse(ChangelogResetMigration.shouldReset(storedLastRevised: "0.0.0"))
        XCTAssertFalse(ChangelogResetMigration.shouldReset(storedLastRevised: nil))
        XCTAssertFalse(ChangelogResetMigration.shouldReset(storedLastRevised: "garbage"))
    }
}
