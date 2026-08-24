//
//  PanelThemeTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for the panel theme (MeetingBarNG): lenient decoding, and the
//  distinction between "follow the system" and "force light".
//

import XCTest

@testable import MeetingBarLogic

final class PanelThemeTests: XCTestCase {
    // MARK: - Decoding

    func testKnownAppearancesDecode() {
        XCTAssertEqual(PanelThemePolicy.appearance(fromRaw: "light"), .light)
        XCTAssertEqual(PanelThemePolicy.appearance(fromRaw: "dark"), .dark)
        XCTAssertEqual(PanelThemePolicy.appearance(fromRaw: "system"), .system)
    }

    func testUnknownAppearanceFallsBackToSystem() {
        // An older build or a hand-edited plist should cost the user their theme,
        // not leave the panel unable to draw.
        XCTAssertEqual(PanelThemePolicy.appearance(fromRaw: "solarized"), .system)
        XCTAssertEqual(PanelThemePolicy.appearance(fromRaw: ""), .system)
    }

    func testKnownAccentsDecode() {
        for accent in PanelAccent.allCases {
            XCTAssertEqual(PanelThemePolicy.accent(fromRaw: accent.rawValue), accent)
        }
    }

    func testUnknownAccentFallsBackToSystem() {
        XCTAssertEqual(PanelThemePolicy.accent(fromRaw: "chartreuse"), .system)
        XCTAssertEqual(PanelThemePolicy.accent(fromRaw: ""), .system)
    }

    func testDecodingIsCaseSensitive() {
        // Raw values are written by the app, never typed by a user, so a
        // case-insensitive match would only ever paper over a real bug.
        XCTAssertEqual(PanelThemePolicy.appearance(fromRaw: "Dark"), .system)
    }

    // MARK: - Forcing

    func testSystemDoesNotForceAnAppearance() {
        // nil is NOT the same as forcing light: a window with no explicit
        // appearance keeps following the system as it changes, where a pinned
        // one would freeze until the next relaunch.
        XCTAssertNil(PanelThemePolicy.forcedAppearance(.system))
    }

    func testExplicitAppearancesAreForced() {
        XCTAssertEqual(PanelThemePolicy.forcedAppearance(.light), .light)
        XCTAssertEqual(PanelThemePolicy.forcedAppearance(.dark), .dark)
    }

    // MARK: - Accent override

    func testSystemAccentDoesNotOverride() {
        XCTAssertFalse(PanelAccent.system.overridesSystem)
    }

    func testEveryOtherAccentOverrides() {
        for accent in PanelAccent.allCases where accent != .system {
            XCTAssertTrue(accent.overridesSystem, "\(accent) should override")
        }
    }

    // MARK: - Defaults

    func testTheDefaultOfBothAxesIsSystem() {
        // The shipping panel must be unchanged until someone chooses otherwise.
        XCTAssertEqual(PanelAppearance.allCases.first, .system)
        XCTAssertEqual(PanelAccent.allCases.first, .system)
    }
}
