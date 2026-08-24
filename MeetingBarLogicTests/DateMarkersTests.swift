//
//  DateMarkersTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for date markers (MeetingBarNG): the storage round trip, what
//  a corrupt entry costs, and which days a marker actually falls on.
//

import XCTest

@testable import MeetingBarLogic

final class DateMarkersTests: XCTestCase {
    private func calendar(timeZone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, timeZone: String = "UTC") -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar(timeZone: timeZone).date(from: components)!
    }

    // MARK: - Encoding round trip

    func testDatedMarkerRoundTrips() {
        let marker = DateMarker(month: 3, day: 7, year: 2027, label: "Launch")
        let encoded = DateMarkerCodec.encode(marker)
        XCTAssertEqual(encoded, "2027-03-07|Launch")
        XCTAssertEqual(DateMarkerCodec.decode(encoded), marker)
    }

    func testRepeatingMarkerRoundTrips() {
        let marker = DateMarker(month: 12, day: 25, label: "Christmas")
        let encoded = DateMarkerCodec.encode(marker)
        XCTAssertEqual(encoded, "-----12-25|Christmas")
        let decoded = DateMarkerCodec.decode(encoded)
        XCTAssertEqual(decoded, marker)
        XCTAssertEqual(decoded?.repeatsAnnually, true)
    }

    func testLabelContainingTheSeparatorSurvives() {
        // Only the FIRST separator splits, so a label may contain one.
        let marker = DateMarker(month: 1, day: 2, year: 2026, label: "Ship v1 | tell the team")
        XCTAssertEqual(DateMarkerCodec.decode(DateMarkerCodec.encode(marker)), marker)
    }

    func testSingleDigitMonthAndDayArePadded() {
        // Padding keeps the stored list sortable as plain text.
        XCTAssertEqual(
            DateMarkerCodec.encode(DateMarker(month: 1, day: 5, year: 2026, label: "x")),
            "2026-01-05|x"
        )
    }

    // MARK: - Corrupt entries

    func testCorruptEntriesAreRejectedIndividually() {
        XCTAssertNil(DateMarkerCodec.decode("nonsense"))
        XCTAssertNil(DateMarkerCodec.decode("2026-01-05"), "no label")
        XCTAssertNil(DateMarkerCodec.decode("2026-01-05|"), "empty label")
        XCTAssertNil(DateMarkerCodec.decode("2026-13-05|bad month"))
        XCTAssertNil(DateMarkerCodec.decode("2026-01-32|bad day"))
    }

    func testAnUnparseableYearIsRejectedRatherThanTreatedAsRepeating() {
        // Silently promoting a corrupt year to "every year" would put a one-off
        // deadline on the grid forever.
        XCTAssertNil(DateMarkerCodec.decode("20x6-01-05|Launch"))
    }

    func testDecodeAllDropsOnlyTheBadEntries() {
        let raws = ["2026-01-05|Good", "garbage", "-----12-25|Christmas"]
        let markers = DateMarkerCodec.decodeAll(raws)
        XCTAssertEqual(markers.count, 2)
        XCTAssertEqual(markers.map(\.label), ["Good", "Christmas"])
    }

    func testEncodeAllRoundTripsAList() {
        let markers = [
            DateMarker(month: 1, day: 5, year: 2026, label: "Launch"),
            DateMarker(month: 12, day: 25, label: "Christmas")
        ]
        XCTAssertEqual(DateMarkerCodec.decodeAll(DateMarkerCodec.encodeAll(markers)), markers)
    }

    // MARK: - Matching

    func testDatedMarkerMatchesOnlyItsOwnYear() {
        let markers = [DateMarker(month: 3, day: 7, year: 2027, label: "Launch")]
        XCTAssertEqual(
            DateMarkerPolicy.markers(on: date(2027, 3, 7), from: markers, calendar: calendar()).count, 1
        )
        XCTAssertTrue(
            DateMarkerPolicy.markers(on: date(2026, 3, 7), from: markers, calendar: calendar()).isEmpty
        )
    }

    func testRepeatingMarkerMatchesEveryYear() {
        let markers = [DateMarker(month: 12, day: 25, label: "Christmas")]
        for year in [2025, 2026, 2031] {
            XCTAssertFalse(
                DateMarkerPolicy.markers(on: date(year, 12, 25), from: markers, calendar: calendar()).isEmpty,
                "should match in \(year)"
            )
        }
    }

    func testWrongDayDoesNotMatch() {
        let markers = [DateMarker(month: 12, day: 25, label: "Christmas")]
        XCTAssertTrue(
            DateMarkerPolicy.markers(on: date(2026, 12, 24), from: markers, calendar: calendar()).isEmpty
        )
    }

    func testFebruary29MatchesOnlyInALeapYear() {
        // Stored happily, matches nothing in a common year — the right behaviour
        // for a marker, rather than an error at entry.
        let markers = [DateMarker(month: 2, day: 29, label: "Leap day")]
        XCTAssertFalse(
            DateMarkerPolicy.markers(on: date(2028, 2, 29), from: markers, calendar: calendar()).isEmpty
        )
        XCTAssertTrue(
            DateMarkerPolicy.markers(on: date(2027, 2, 28), from: markers, calendar: calendar()).isEmpty
        )
    }

    func testMatchingIsByCalendarDayNotInstant() {
        // The whole reason components are stored instead of a Date: the same
        // marker must land on 25 December in every time zone.
        let markers = [DateMarker(month: 12, day: 25, label: "Christmas")]
        for zone in ["UTC", "Australia/Sydney", "America/Chicago", "Pacific/Kiritimati"] {
            let calendar = calendar(timeZone: zone)
            let christmas = date(2026, 12, 25, timeZone: zone)
            XCTAssertFalse(
                DateMarkerPolicy.markers(on: christmas, from: markers, calendar: calendar).isEmpty,
                "should match in \(zone)"
            )
        }
    }

    func testSeveralMarkersOnOneDayAreAllReturnedInStoredOrder() {
        let markers = [
            DateMarker(month: 6, day: 1, label: "Birthday"),
            DateMarker(month: 6, day: 1, year: 2026, label: "Deadline")
        ]
        let hits = DateMarkerPolicy.markers(on: date(2026, 6, 1), from: markers, calendar: calendar())
        XCTAssertEqual(hits.map(\.label), ["Birthday", "Deadline"])
    }

    func testHasMarkerAgreesWithMarkers() {
        let markers = [DateMarker(month: 6, day: 1, label: "Birthday")]
        XCTAssertTrue(DateMarkerPolicy.hasMarker(on: date(2026, 6, 1), from: markers, calendar: calendar()))
        XCTAssertFalse(DateMarkerPolicy.hasMarker(on: date(2026, 6, 2), from: markers, calendar: calendar()))
    }
}
