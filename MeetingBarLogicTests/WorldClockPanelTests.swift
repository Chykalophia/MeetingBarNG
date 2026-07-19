//
//  WorldClockPanelTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for the multi-zone world-clock panel policy (MeetingBarNG).
//

import XCTest

@testable import MeetingBarLogic

final class WorldClockPanelTests: XCTestCase {
    private let locale = Locale(identifier: "en_US_POSIX")

    private let la = TimeZone(identifier: "America/Los_Angeles")!
    private let utc = TimeZone(identifier: "UTC")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    /// Builds a deterministic instant from calendar components in `zone`.
    private func instant(
        year: Int, month: Int, day: Int, hour: Int, minute: Int = 0, zone: TimeZone
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = locale
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )!
    }

    private func assertMatches(
        _ value: String,
        _ pattern: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNotNil(
            value.range(of: pattern, options: .regularExpression),
            "\"\(value)\" did not match /\(pattern)/",
            file: file, line: line
        )
    }

    // MARK: - timeText: differs by zone

    func testTimeDiffersByZone() {
        // 2026-01-01 20:00 UTC → LA 12:00, UTC 20:00, Tokyo (next day) 05:00.
        let now = instant(year: 2026, month: 1, day: 1, hour: 20, zone: utc)
        let laTime = WorldClockPanelPolicy.timeText(now: now, timeZone: la, use24Hour: true, locale: locale)
        let utcTime = WorldClockPanelPolicy.timeText(now: now, timeZone: utc, use24Hour: true, locale: locale)
        let tokyoTime = WorldClockPanelPolicy.timeText(now: now, timeZone: tokyo, use24Hour: true, locale: locale)

        // The localized 24-hour skeleton "Hmm" resolves to a zero-padded "HH:mm"
        // pattern for en_US_POSIX, so single-digit hours read as e.g. "05:00".
        XCTAssertEqual(laTime, "12:00")
        XCTAssertEqual(utcTime, "20:00")
        XCTAssertEqual(tokyoTime, "05:00")
        XCTAssertNotEqual(laTime, utcTime)
        XCTAssertNotEqual(utcTime, tokyoTime)
    }

    // MARK: - dayOffset: across the date line

    func testDayOffsetTomorrowAcrossDateLine() {
        // At 2026-01-01 20:00 UTC it is still Jan 1 in LA but already Jan 2 in
        // Tokyo, so Tokyo is "tomorrow" relative to an LA reference.
        let now = instant(year: 2026, month: 1, day: 1, hour: 20, zone: utc)
        XCTAssertEqual(
            WorldClockPanelPolicy.dayOffset(now: now, zone: tokyo, referenceZone: la, locale: locale),
            1
        )
    }

    func testDayOffsetYesterdayAcrossDateLine() {
        // Same instant, reversed reference: LA is "yesterday" relative to Tokyo.
        let now = instant(year: 2026, month: 1, day: 1, hour: 20, zone: utc)
        XCTAssertEqual(
            WorldClockPanelPolicy.dayOffset(now: now, zone: la, referenceZone: tokyo, locale: locale),
            -1
        )
    }

    func testDayOffsetSameZoneIsZero() {
        let now = instant(year: 2026, month: 1, day: 1, hour: 20, zone: utc)
        XCTAssertEqual(
            WorldClockPanelPolicy.dayOffset(now: now, zone: la, referenceZone: la, locale: locale),
            0
        )
        XCTAssertEqual(
            WorldClockPanelPolicy.dayOffset(now: now, zone: utc, referenceZone: utc, locale: locale),
            0
        )
    }

    // MARK: - 24h vs 12h formatting

    func testFormat24HourHasNoMeridiem() {
        let now = instant(year: 2026, month: 6, day: 15, hour: 21, minute: 5, zone: utc)
        let result = WorldClockPanelPolicy.timeText(now: now, timeZone: utc, use24Hour: true, locale: locale)
        assertMatches(result, "^[0-9]{1,2}:[0-9]{2}$")
        XCTAssertFalse(result.contains("AM"))
        XCTAssertFalse(result.contains("PM"))
        XCTAssertEqual(result, "21:05")
    }

    func testFormat12HourHasMeridiem() {
        let now = instant(year: 2026, month: 6, day: 15, hour: 21, minute: 5, zone: utc)
        let result = WorldClockPanelPolicy.timeText(now: now, timeZone: utc, use24Hour: false, locale: locale)
        XCTAssertTrue(result.contains("PM"), result)
        XCTAssertTrue(result.contains("9"), result)
        XCTAssertFalse(result.contains("21"), result)
    }

    // MARK: - cityLabel derivation

    func testCityLabelStripsRegionAndUnderscores() {
        XCTAssertEqual(WorldClockPanelPolicy.cityLabel(fromIdentifier: "America/Los_Angeles"), "Los Angeles")
        XCTAssertEqual(WorldClockPanelPolicy.cityLabel(fromIdentifier: "Europe/Isle_of_Man"), "Isle of Man")
        XCTAssertEqual(WorldClockPanelPolicy.cityLabel(fromIdentifier: "Asia/Tokyo"), "Tokyo")
    }

    func testCityLabelWithoutRegionIsUnchanged() {
        XCTAssertEqual(WorldClockPanelPolicy.cityLabel(fromIdentifier: "UTC"), "UTC")
    }

    // MARK: - entries

    func testEntriesPreservesOrderAndComputesFields() {
        let now = instant(year: 2026, month: 1, day: 1, hour: 20, zone: utc)
        let entries = WorldClockPanelPolicy.entries(
            zones: [
                WorldClockZone(identifier: "America/Los_Angeles", label: "Los Angeles"),
                WorldClockZone(identifier: "Asia/Tokyo", label: "Tokyo")
            ],
            now: now,
            use24Hour: true,
            referenceZone: la,
            locale: locale
        )

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0], WorldClockEntry(label: "Los Angeles", time: "12:00", dayOffset: 0))
        XCTAssertEqual(entries[1], WorldClockEntry(label: "Tokyo", time: "05:00", dayOffset: 1))
    }

    func testEntriesEmptyZonesReturnsEmpty() {
        let now = instant(year: 2026, month: 1, day: 1, hour: 20, zone: utc)
        XCTAssertEqual(
            WorldClockPanelPolicy.entries(
                zones: [], now: now, use24Hour: true, referenceZone: utc, locale: locale
            ),
            []
        )
    }

    func testEntriesUnknownIdentifierFallsBackToReferenceZone() {
        let now = instant(year: 2026, month: 1, day: 1, hour: 20, zone: utc)
        let entries = WorldClockPanelPolicy.entries(
            zones: [WorldClockZone(identifier: "Not/AZone", label: "Bogus")],
            now: now,
            use24Hour: true,
            referenceZone: utc,
            locale: locale
        )
        XCTAssertEqual(entries, [WorldClockEntry(label: "Bogus", time: "20:00", dayOffset: 0)])
    }
}
