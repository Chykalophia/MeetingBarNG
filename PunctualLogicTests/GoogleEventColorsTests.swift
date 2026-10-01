//
//  GoogleEventColorsTests.swift
//  MeetingBarLogicTests
//
//  Google's per-event colour palette — the detail that lets the dropdown's
//  timeline show a day the way Google Calendar does, rather than one flat
//  colour per calendar. EventKit has no equivalent, so this is direct-provider
//  only.
//

import XCTest

@testable import PunctualLogic

final class GoogleEventColorsTests: XCTestCase {
    /// The shape `/colors` actually returns.
    private let response: [String: Any] = [
        "kind": "calendar#colors",
        "updated": "2012-02-14T00:00:00.000Z",
        "calendar": [
            "1": ["background": "#ac725e", "foreground": "#1d1d1d"]
        ],
        "event": [
            "1": ["background": "#a4bdfc", "foreground": "#1d1d1d"],
            "11": ["background": "#dc2127", "foreground": "#1d1d1d"]
        ]
    ]

    func test_parsesTheEventPalette() {
        let palette = GoogleColorPalette.parse(response)
        XCTAssertEqual(palette.background(forEventColorID: "1"), "#a4bdfc")
        XCTAssertEqual(palette.background(forEventColorID: "11"), "#dc2127")
    }

    /// Calendar colours arrive on the calendarList entries as a literal
    /// `backgroundColor`, so the calendar palette is a second way to learn
    /// something already known — and mixing the two would colour events with
    /// the wrong set entirely.
    func test_calendarPaletteIsNotUsedForEvents() {
        let palette = GoogleColorPalette.parse(response)
        XCTAssertNotEqual(
            palette.background(forEventColorID: "1"), "#ac725e",
            "event colorId 1 must resolve from the EVENT palette")
    }

    // MARK: - Falling back rather than inventing
    //
    // Every one of these means "use the calendar's colour", which is what the
    // app did before per-event colours existed. A wrong colour would be worse
    // than the old flat one.

    func test_noColorIDMeansNoOverride() {
        let palette = GoogleColorPalette.parse(response)
        XCTAssertNil(palette.background(forEventColorID: nil))
        XCTAssertNil(palette.background(forEventColorID: ""))
    }

    func test_unknownColorIDMeansNoOverride() {
        // Google adding a twelfth colour must not render as black.
        let palette = GoogleColorPalette.parse(response)
        XCTAssertNil(palette.background(forEventColorID: "12"))
    }

    func test_responseWithoutAnEventPaletteIsEmpty() {
        XCTAssertTrue(GoogleColorPalette.parse(["kind": "calendar#colors"]).isEmpty)
        XCTAssertTrue(GoogleColorPalette.parse([:]).isEmpty)
    }

    func test_entriesWithoutAUsableBackgroundAreDropped() {
        let palette = GoogleColorPalette.parse([
            "event": [
                "1": ["foreground": "#1d1d1d"],
                "2": ["background": 42],
                "3": ["background": "not-a-colour"],
                "4": ["background": "#a4bdfc"]
            ]
        ])
        XCTAssertNil(palette.background(forEventColorID: "1"))
        XCTAssertNil(palette.background(forEventColorID: "2"))
        XCTAssertNil(
            palette.background(forEventColorID: "3"),
            "a malformed value must be dropped here, not reach the UI as black")
        XCTAssertEqual(palette.background(forEventColorID: "4"), "#a4bdfc")
    }

    // MARK: - Hex validation

    func test_hexValidationAcceptsBothLengths() {
        XCTAssertTrue(GoogleColorPalette.isHexColor("#a4bdfc"))
        XCTAssertTrue(GoogleColorPalette.isHexColor("#abc"))
    }

    func test_hexValidationRejectsTheRest() {
        for bad in ["a4bdfc", "#a4bdf", "#a4bdfcc", "#gggggg", "#", ""] {
            XCTAssertFalse(GoogleColorPalette.isHexColor(bad), "\(bad) should be rejected")
        }
    }

    func test_emptyPaletteOverridesNothing() {
        XCTAssertNil(GoogleColorPalette.empty.background(forEventColorID: "1"))
    }
}
