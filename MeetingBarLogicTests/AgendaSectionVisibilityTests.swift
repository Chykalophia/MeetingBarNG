//
//  AgendaSectionVisibilityTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for "hide empty days" (MeetingBarNG): which day sections the
//  agenda draws, and the one it must never hide.
//

import XCTest

@testable import MeetingBarLogic

final class AgendaSectionVisibilityTests: XCTestCase {
    private func shows(
        count: Int,
        included: Bool = true,
        hidesEmpty: Bool,
        anchor: Bool = false
    ) -> Bool {
        AgendaSectionVisibilityPolicy.showsSection(
            eventCount: count,
            isIncludedByPeriod: included,
            hidesEmptyDays: hidesEmpty,
            isAnchorDay: anchor
        )
    }

    // MARK: - The setting off: nothing changes

    func testEmptyLookAheadDayStillShowsWhenTheSettingIsOff() {
        // The shipping behaviour. An upgrade must not silently drop a section.
        XCTAssertTrue(shows(count: 0, hidesEmpty: false))
    }

    func testPopulatedDayShowsEitherWay() {
        XCTAssertTrue(shows(count: 3, hidesEmpty: false))
        XCTAssertTrue(shows(count: 3, hidesEmpty: true))
    }

    // MARK: - The setting on

    func testEmptyLookAheadDayIsHiddenWhenTheSettingIsOn() {
        XCTAssertFalse(shows(count: 0, hidesEmpty: true))
    }

    func testOneEventIsEnoughToKeepTheSection() {
        XCTAssertTrue(shows(count: 1, hidesEmpty: true))
    }

    // MARK: - Today is never hidden

    func testTodayShowsEvenWhenEmptyAndHidingIsOn() {
        // An agenda with no headings at all reads as a broken panel, not a free
        // day — and "nothing today" is the most useful thing it can say.
        XCTAssertTrue(shows(count: 0, hidesEmpty: true, anchor: true))
    }

    func testTodayShowsEmptyRegardlessOfTheSetting() {
        XCTAssertTrue(shows(count: 0, hidesEmpty: false, anchor: true))
    }

    // MARK: - The period wins over everything

    func testDayOutsideTheLookAheadPeriodIsNeverShown() {
        // A day the user did not ask for is not "empty" — it is out of scope, and
        // that is decided before the empty question.
        XCTAssertFalse(shows(count: 5, included: false, hidesEmpty: false))
        XCTAssertFalse(shows(count: 5, included: false, hidesEmpty: true))
        XCTAssertFalse(shows(count: 0, included: false, hidesEmpty: true))
    }

    func testAnchorDayStillObeysThePeriod() {
        // Belt and braces: "today is never hidden" must not outrank a period that
        // excludes it, or a caller could draw a section it never asked for.
        XCTAssertFalse(shows(count: 0, included: false, hidesEmpty: true, anchor: true))
    }
}
