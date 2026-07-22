//
//  AlertsPresentationTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for the Alerts pane's permission-state mapping (Preferences
//  UX overhaul, Phase 2). The pane must say what macOS actually allows — and
//  must say NOTHING when everything is fine, because a warning that is always
//  on screen is wallpaper and stops being read.
//

import XCTest

@testable import MeetingBarLogic

final class AlertsPresentationTests: XCTestCase {
    /// The English catalog, parsed from the repo (not a bundle): these tests run
    /// under `swift test` with no host app, so there is no bundle to read.
    /// NOTE: those directory names contain real trailing spaces.
    private static let englishCatalog: [String: String] = {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MeetingBarLogicTests
            .deletingLastPathComponent()  // repo root
        let strings = repoRoot
            .appendingPathComponent("MeetingBarNG")
            .appendingPathComponent("Resources ")
            .appendingPathComponent("Localization ")
            .appendingPathComponent("en.lproj")
            .appendingPathComponent("Localizable.strings")
        return NSDictionary(contentsOf: strings) as? [String: String] ?? [:]
    }()

    // MARK: - Resolution

    func testDeniedMeansNothingReachesYou() {
        XCTAssertEqual(
            NotificationDeliveryPolicy.resolve(authorization: .denied, staysOnscreen: true),
            .blocked
        )
        // The alert style is irrelevant once macOS is refusing to deliver.
        XCTAssertEqual(
            NotificationDeliveryPolicy.resolve(authorization: .denied, staysOnscreen: false),
            .blocked
        )
    }

    func testNotDeterminedIsTreatedAsBlocked() {
        // Nothing arrives until macOS has been asked and said yes, so the pane
        // must not claim the alerts below it are working.
        XCTAssertEqual(
            NotificationDeliveryPolicy.resolve(authorization: .notDetermined, staysOnscreen: true),
            .blocked
        )
    }

    func testAllowedSplitsOnWhetherTheyStayOnscreen() {
        XCTAssertEqual(
            NotificationDeliveryPolicy.resolve(authorization: .allowed, staysOnscreen: true),
            .persistent
        )
        XCTAssertEqual(
            NotificationDeliveryPolicy.resolve(authorization: .allowed, staysOnscreen: false),
            .disappearing
        )
    }

    // MARK: - What the pane shows

    func testTheCalmStateSaysNothingAndOffersNoButton() {
        XCTAssertNil(NotificationDelivery.persistent.messageKey)
        XCTAssertFalse(NotificationDelivery.persistent.offersSettingsButton)
        XCTAssertFalse(NotificationDelivery.persistent.isProblem)
    }

    func testEveryOtherStateOffersTheButtonRatherThanInstructions() {
        for delivery in [NotificationDelivery.blocked, .disappearing] {
            XCTAssertNotNil(delivery.messageKey, "\(delivery.rawValue) has nothing to say")
            XCTAssertTrue(
                delivery.offersSettingsButton,
                "\(delivery.rawValue) must offer a real button, not prose telling the user to go find System Settings"
            )
        }
    }

    func testOnlyBlockedReadsAsAProblem() {
        XCTAssertTrue(NotificationDelivery.blocked.isProblem)
        // Banners still arrive — that is advice, not a failure.
        XCTAssertFalse(NotificationDelivery.disappearing.isProblem)
    }

    func testEveryMessageKeyIsDefinedInEnglish() {
        XCTAssertFalse(Self.englishCatalog.isEmpty, "en.lproj failed to parse")
        for delivery in NotificationDelivery.allCases {
            guard let key = delivery.messageKey else { continue }
            XCTAssertNotNil(
                Self.englishCatalog[key],
                "\(delivery.rawValue): '\(key)' is not defined in en.lproj"
            )
        }
        XCTAssertNotNil(Self.englishCatalog[NotificationDelivery.settingsButtonKey])
    }
}
