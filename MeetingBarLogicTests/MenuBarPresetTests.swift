//
//  MenuBarPresetTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for the composable menu-bar PRESETS (MeetingBarNG, Dot
//  parity): the preset→tokens map and the `detect` round-trip.
//

import XCTest

@testable import MeetingBarLogic

final class MenuBarPresetTests: XCTestCase {
    // MARK: - Token maps

    func testPresetTokenMaps() {
        XCTAssertEqual(MenuBarPreset.classic.tokens, [.icon, .title, .countdown])
        XCTAssertEqual(MenuBarPreset.minimal.tokens, [.icon, .title])
        XCTAssertEqual(MenuBarPreset.agenda.tokens, [.title, .countdown])
        XCTAssertEqual(MenuBarPreset.info.tokens, [.icon, .date, .clock])
    }

    func testCustomTokensAreEmptySentinel() {
        XCTAssertTrue(MenuBarPreset.custom.tokens.isEmpty)
    }

    // MARK: - detect

    func testDetectRoundTripsEachNamedPreset() {
        for preset in MenuBarPreset.allCases where preset != .custom {
            XCTAssertEqual(
                MenuBarPreset.detect(tokens: preset.tokens), preset,
                "\(preset.rawValue) should round-trip through detect"
            )
        }
    }

    func testNonMatchingOrderDetectsAsCustom() {
        // The classic token set, reordered — not an exact ordered match.
        XCTAssertEqual(MenuBarPreset.detect(tokens: [.title, .icon, .countdown]), .custom)
    }

    func testUnusedTokenSetDetectsAsCustom() {
        // A token combination no named preset uses.
        XCTAssertEqual(MenuBarPreset.detect(tokens: [.progress, .weekNumber]), .custom)
    }

    func testEmptyDetectsAsClassic() {
        XCTAssertEqual(MenuBarPreset.detect(tokens: []), .classic)
    }
}
