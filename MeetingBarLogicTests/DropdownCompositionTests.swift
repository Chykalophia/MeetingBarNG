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
            [.greeting, .upNext, .timeline, .meeting, .calendar, .agenda, .join, .bookmarks]
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
        // Unknowns vanish; remaining modules keep their GIVEN order (greeting then
        // timeline), and only then do the missing standard modules append — which
        // is why `upNext` lands after `timeline` here despite preceding it in
        // `standard`. The stored order wins for anything it mentions.
        XCTAssertEqual(
            resolved,
            [.greeting, .timeline, .upNext, .meeting, .calendar, .agenda, .join, .bookmarks]
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
            [.greeting, .timeline, .agenda, .join, .bookmarks, .upNext, .meeting, .calendar]
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
            [.bookmarks, .greeting, .upNext, .timeline, .meeting, .calendar, .agenda, .join]
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

    // MARK: - enabledRawValues (shared by the controller + Display-tab preview)

    func testEnabledRawValuesReflectsEachToggle() {
        XCTAssertEqual(
            DropdownCompositionPolicy.enabledRawValues(
                greeting: true, timeline: false, meeting: true,
                agenda: false, join: true, bookmarks: false, calendar: false, upNext: false
            ),
            ["greeting", "meeting", "join"]
        )
    }

    func testEnabledRawValuesAllOnMatchesEveryModule() {
        XCTAssertEqual(
            DropdownCompositionPolicy.enabledRawValues(
                greeting: true, timeline: true, meeting: true,
                agenda: true, join: true, bookmarks: true, calendar: true, upNext: true
            ),
            allEnabled
        )
    }

    func testEnabledRawValuesAllOffIsEmpty() {
        XCTAssertTrue(
            DropdownCompositionPolicy.enabledRawValues(
                greeting: false, timeline: false, meeting: false,
                agenda: false, join: false, bookmarks: false, calendar: false, upNext: false
            ).isEmpty
        )
    }

    /// The controller resolves the real dropdown by feeding `enabledRawValues`
    /// into `resolve`; the preview must produce the identical module list from the
    /// same toggles, so exercise the two together.
    func testEnabledRawValuesFeedsResolveDeterministically() {
        let enabled = DropdownCompositionPolicy.enabledRawValues(
            greeting: true, timeline: false, meeting: true,
            agenda: true, join: false, bookmarks: false, calendar: false, upNext: false
        )
        let resolved = DropdownCompositionPolicy.resolve(order: standardOrderRaw, enabled: enabled)
        XCTAssertEqual(resolved, [.greeting, .meeting, .agenda])
    }
}
