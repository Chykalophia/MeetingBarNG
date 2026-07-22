//
//  FilterPresetsTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for the Filters pane's pure logic (Preferences UX overhaul,
//  Phase 2): preset apply/detect round-trips, the ended-meetings merge of two
//  keys into one row, and the retirement of the "show as underlined" value.
//

import XCTest

@testable import MeetingBarLogic

final class FilterPresetsTests: XCTestCase {
    // MARK: - Presets

    func testApplyingAPresetThenDetectingReturnsTheSamePreset() {
        for preset in FilterPreset.allCases where preset != .custom {
            XCTAssertEqual(
                FilterPreset.detect(preset.values),
                preset,
                "\(preset.rawValue) does not round-trip"
            )
        }
    }

    func testUnmatchedValuesReadAsCustomWithoutStoringAnything() {
        var tuned = FilterPreset.everything.values
        tuned[FilterDefaultsKey.declined] = "hide"
        XCTAssertEqual(FilterPreset.detect(tuned), .custom)
        // `.custom` writes nothing, so picking it can never destroy a layout.
        XCTAssertTrue(FilterPreset.custom.values.isEmpty)
    }

    func testEveryPresetCoversEverySevenRowsPlusTheMergedKey() {
        let expected: Set<String> = [
            FilterDefaultsKey.allDay,
            FilterDefaultsKey.noLink,
            FilterDefaultsKey.solo,
            FilterDefaultsKey.pending,
            FilterDefaultsKey.tentative,
            FilterDefaultsKey.declined,
            FilterDefaultsKey.ended,
            FilterDefaultsKey.hideFinished
        ]
        for preset in FilterPreset.allCases where preset != .custom {
            XCTAssertEqual(
                Set(preset.values.keys),
                expected,
                "\(preset.rawValue) leaves a filter row untouched, so the chip lies about what it did"
            )
        }
    }

    func testAcceptedOnlyIsStricterThanMeetingsOnly() {
        XCTAssertEqual(FilterPreset.meetingsOnly.values[FilterDefaultsKey.pending], "show")
        XCTAssertEqual(FilterPreset.acceptedOnly.values[FilterDefaultsKey.pending], "hide")
        XCTAssertEqual(FilterPreset.acceptedOnly.values[FilterDefaultsKey.tentative], "hide")
    }

    func testEveryPresetTitleKeyIsDistinct() {
        let keys = FilterPreset.allCases.map(\.titleKey)
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    // MARK: - Ended meetings (two keys, one row)

    func testEitherKeyAskingToHideHides() {
        XCTAssertEqual(
            EndedMeetingsVisibility.resolve(pastRawValue: "show_active", hideFinished: true),
            .hide
        )
        XCTAssertEqual(
            EndedMeetingsVisibility.resolve(pastRawValue: "hide", hideFinished: false),
            .hide
        )
        XCTAssertEqual(
            EndedMeetingsVisibility.resolve(pastRawValue: "show_inactive", hideFinished: true),
            .hide
        )
    }

    func testDimAndShowAreReadFromThePastKeyWhenNothingHides() {
        XCTAssertEqual(
            EndedMeetingsVisibility.resolve(pastRawValue: "show_inactive", hideFinished: false),
            .dim
        )
        XCTAssertEqual(
            EndedMeetingsVisibility.resolve(pastRawValue: "show_active", hideFinished: false),
            .show
        )
    }

    func testWritingTheRowKeepsBothKeysConsistent() {
        for visibility in FilterVisibility.allCases {
            let stored = EndedMeetingsVisibility.storedValues(for: visibility)
            XCTAssertEqual(
                EndedMeetingsVisibility.resolve(
                    pastRawValue: stored.past,
                    hideFinished: stored.hideFinished
                ),
                visibility,
                "\(visibility.rawValue) does not round-trip through both keys"
            )
        }
    }

    func testAnUnknownStoredValueDegradesToShowRatherThanVanishing() {
        XCTAssertEqual(
            EndedMeetingsVisibility.resolve(pastRawValue: "who_knows", hideFinished: false),
            .show
        )
    }

    // MARK: - Retired vocabulary

    func testUnderlinedMigratesToDimAndEverythingElseIsLeftAlone() {
        XCTAssertEqual(FilterVocabularyMigration.migrated("show_underlined"), "show_inactive")
        XCTAssertNil(FilterVocabularyMigration.migrated("show"))
        XCTAssertNil(FilterVocabularyMigration.migrated("show_inactive"))
        XCTAssertNil(FilterVocabularyMigration.migrated("hide"))
    }

    func testMigrationIsIdempotent() {
        let once = FilterVocabularyMigration.migrated("show_underlined") ?? "show_underlined"
        XCTAssertNil(FilterVocabularyMigration.migrated(once))
    }
}
