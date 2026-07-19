//
//  DropdownCompositionTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for the composable menu dropdown policy (MeetingBarNG).
//

import XCTest

@testable import MeetingBarLogic

final class DropdownCompositionTests: XCTestCase {
    private let allEnabled = Set(DropdownModule.allCases.map(\.rawValue))
    private var standardOrderRaw: [String] {
        DropdownComposition.standard.modules.map(\.rawValue)
    }

    func testStandardIsTheClassicOrder() {
        XCTAssertEqual(
            DropdownComposition.standard.modules,
            [.greeting, .timeline, .meeting, .agenda, .join, .bookmarks]
        )
    }

    func testDefaultOrderResolvesToStandard() {
        let resolved = DropdownCompositionPolicy.resolve(
            order: standardOrderRaw,
            enabled: allEnabled
        )
        XCTAssertEqual(resolved, DropdownComposition.standard.modules)
    }

    func testEmptyOrderYieldsAllStandardModules() {
        let resolved = DropdownCompositionPolicy.resolve(order: [], enabled: allEnabled)
        XCTAssertEqual(resolved, DropdownComposition.standard.modules)
    }

    func testUnknownRawStringsAreDropped() {
        let resolved = DropdownCompositionPolicy.resolve(
            order: ["greeting", "made_up_module", "timeline", ""],
            enabled: allEnabled
        )
        // Unknowns vanish; remaining modules keep their given order, then the
        // missing standard modules append in standard order.
        XCTAssertEqual(
            resolved,
            [.greeting, .timeline, .meeting, .agenda, .join, .bookmarks]
        )
    }

    func testMissingModuleAppendsInStandardPosition() {
        // `meeting` is absent from the stored order; it should reappear at its
        // standard position relative to the other appended modules.
        let resolved = DropdownCompositionPolicy.resolve(
            order: ["greeting", "timeline", "agenda", "join", "bookmarks"],
            enabled: allEnabled
        )
        XCTAssertEqual(
            resolved,
            [.greeting, .timeline, .agenda, .join, .bookmarks, .meeting]
        )
    }

    func testDuplicatesAreDeduplicatedFirstWins() {
        let resolved = DropdownCompositionPolicy.resolve(
            order: ["bookmarks", "greeting", "bookmarks", "greeting"],
            enabled: allEnabled
        )
        // First occurrence of each wins; the rest append in standard order.
        XCTAssertEqual(
            resolved,
            [.bookmarks, .greeting, .timeline, .meeting, .agenda, .join]
        )
    }

    func testEnabledFilterRemovesDisabledModules() {
        let resolved = DropdownCompositionPolicy.resolve(
            order: standardOrderRaw,
            enabled: ["greeting", "meeting", "join"]
        )
        XCTAssertEqual(resolved, [.greeting, .meeting, .join])
    }

    func testEnabledFilterKeepsCustomOrder() {
        let resolved = DropdownCompositionPolicy.resolve(
            order: ["join", "meeting", "greeting", "timeline", "agenda", "bookmarks"],
            enabled: ["join", "greeting"]
        )
        XCTAssertEqual(resolved, [.join, .greeting])
    }

    func testEmptyEnabledYieldsNothing() {
        let resolved = DropdownCompositionPolicy.resolve(
            order: standardOrderRaw,
            enabled: []
        )
        XCTAssertTrue(resolved.isEmpty)
    }
}
