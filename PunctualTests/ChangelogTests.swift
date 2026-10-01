//
//  ChangelogTests.swift
//  MeetingBarTests
//
//  The typed release-notes model and the sub-1.0 version-reset migration.
//

import XCTest

@testable import Punctual

final class ChangelogTests: XCTestCase {
    func testEveryReleaseSurfacesForAFreshInstallNewestFirst() {
        let unseen = ReleaseNotes.releases(newerThan: "0.0.0")
        XCTAssertEqual(unseen.map(\.version), ["1.0.0", "0.1.0"])
    }

    func testOnlyTheNewerReleaseSurfacesAfterAcknowledgingAnOlderOne() {
        XCTAssertEqual(ReleaseNotes.releases(newerThan: "0.1.0").map(\.version), ["1.0.0"])
    }

    func testNothingSurfacesOnceTheLatestIsAcknowledged() {
        XCTAssertTrue(ReleaseNotes.releases(newerThan: "1.0.0").isEmpty)
        // And the acknowledged releases move under "earlier releases".
        XCTAssertEqual(
            ReleaseNotes.releases(upToAndIncluding: "1.0.0").map(\.version), ["1.0.0", "0.1.0"]
        )
    }

    func testTheNewestReleaseNoteMatchesTheShippingVersion() {
        // A release without its own What's New entry would show users the
        // previous version's notes as if they were new.
        let shipping = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        XCTAssertEqual(ReleaseNotes.all.first?.version, shipping)
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
