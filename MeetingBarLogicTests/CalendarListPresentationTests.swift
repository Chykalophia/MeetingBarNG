//
//  CalendarListPresentationTests.swift
//  MeetingBarLogicTests
//
//  The Calendars pane's list is the one place a user answers "which calendars do
//  my meetings come from?", and the shipping app answered it with a flat list
//  that could show "Family" twice with nothing to tell the two apart. These tests
//  pin the fix: group by account, and show the account email under a name that
//  appears more than once.
//

import XCTest

@testable import MeetingBarLogic

final class CalendarListPresentationTests: XCTestCase {
    private func item(
        _ id: String,
        _ title: String,
        source: String,
        email: String? = nil
    ) -> CalendarPickerItem {
        CalendarPickerItem(id: id, title: title, source: source, email: email)
    }

    // MARK: - Grouping by account

    func testCalendarsAreGroupedByAccount() {
        let groups = CalendarListPresentation.groups(for: [
            item("1", "Work", source: "iCloud", email: "me@icloud.com"),
            item("2", "Team", source: "Google", email: "me@work.com"),
            item("3", "Personal", source: "iCloud", email: "me@icloud.com")
        ])

        XCTAssertEqual(groups.map(\.id), ["Google", "iCloud"])
        XCTAssertEqual(groups[0].rows.map(\.id), ["2"])
        XCTAssertEqual(groups[1].rows.map(\.id), ["3", "1"])
    }

    func testUnknownSourceRendersAsOtherAndSortsLast() {
        let groups = CalendarListPresentation.groups(for: [
            item("1", "Odd one", source: CalendarListPresentation.unknownSource),
            item("2", "Work", source: "iCloud")
        ])

        XCTAssertEqual(groups.map(\.id), ["iCloud", CalendarListPresentation.unknownSource])
        XCTAssertNil(groups[0].titleKey)
        XCTAssertEqual(groups[0].title, "iCloud")
        XCTAssertEqual(groups[1].titleKey, "preferences_calendars_source_other")
    }

    // MARK: - Duplicate names

    func testDuplicateNamesGainTheAccountEmail() {
        // The live bug: two calendars both called "Family", one in each account.
        let groups = CalendarListPresentation.groups(for: [
            item("1", "Family", source: "iCloud", email: "me@icloud.com"),
            item("2", "Family", source: "Google", email: "me@gmail.com"),
            item("3", "Work", source: "Google", email: "me@gmail.com")
        ])

        let rows = groups.flatMap(\.rows)
        XCTAssertEqual(rows.first { $0.id == "1" }?.subtitle, "me@icloud.com")
        XCTAssertEqual(rows.first { $0.id == "2" }?.subtitle, "me@gmail.com")
        // "Work" is unambiguous, so it stays a single clean line.
        XCTAssertNil(rows.first { $0.id == "3" }?.subtitle)
    }

    func testDuplicateNamesAreDetectedIgnoringCaseAndAccents() {
        let groups = CalendarListPresentation.groups(for: [
            item("1", "Família", source: "iCloud", email: "a@example.com"),
            item("2", "familia", source: "Google", email: "b@example.com")
        ])

        XCTAssertEqual(groups.flatMap(\.rows).compactMap(\.subtitle).sorted(), [
            "a@example.com", "b@example.com"
        ])
    }

    func testDuplicateNameWithNoEmailHasNoSubtitle() {
        // Nothing is invented: an account with no address gets no fake one.
        let groups = CalendarListPresentation.groups(for: [
            item("1", "Family", source: "iCloud"),
            item("2", "Family", source: "Google")
        ])

        XCTAssertTrue(groups.flatMap(\.rows).allSatisfy { $0.subtitle == nil })
    }

    // MARK: - Search

    func testSearchMatchesTitleAccountAndEmail() {
        let items = [
            item("1", "Work", source: "iCloud", email: "me@icloud.com"),
            item("2", "Team", source: "Google", email: "me@work.com"),
            item("3", "Birthdays", source: "iCloud", email: "me@icloud.com")
        ]

        XCTAssertEqual(
            CalendarListPresentation.groups(for: items, query: "birth").flatMap(\.rows).map(\.id),
            ["3"]
        )
        // The account name is searchable, so "google" narrows to that account.
        XCTAssertEqual(
            CalendarListPresentation.groups(for: items, query: "google").flatMap(\.rows).map(\.id),
            ["2"]
        )
        // So is the address, which is the only place "work.com" appears.
        XCTAssertEqual(
            CalendarListPresentation.groups(for: items, query: "work.com").flatMap(\.rows).map(\.id),
            ["2"]
        )
    }

    func testSearchIsCaseAndAccentInsensitiveAndDropsEmptyGroups() {
        let groups = CalendarListPresentation.groups(
            for: [
                item("1", "Família", source: "iCloud"),
                item("2", "Work", source: "Google")
            ],
            query: "FAMILIA"
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].id, "iCloud")
    }

    func testSearchKeepsTheDisambiguatorItWouldOtherwiseHide() {
        // Narrowing to one "Family" must not drop the email: the user is
        // searching precisely because the two names collide.
        let groups = CalendarListPresentation.groups(
            for: [
                item("1", "Family", source: "iCloud", email: "me@icloud.com"),
                item("2", "Family", source: "Google", email: "me@gmail.com")
            ],
            query: "icloud"
        )

        XCTAssertEqual(groups.flatMap(\.rows).map(\.subtitle), ["me@icloud.com"])
    }

    func testBlankQueryReturnsEverything() {
        let items = [item("1", "Work", source: "iCloud"), item("2", "Team", source: "Google")]
        XCTAssertEqual(CalendarListPresentation.groups(for: items, query: "   ").count, 2)
    }

    // MARK: - All / None

    func testVisibleIDsFollowDisplayOrder() {
        let groups = CalendarListPresentation.groups(for: [
            item("1", "Work", source: "iCloud"),
            item("2", "Team", source: "Google"),
            item("3", "Alpha", source: "iCloud")
        ])

        // "All" and "None" act on exactly what is on screen, in reading order.
        XCTAssertEqual(CalendarListPresentation.visibleIDs(in: groups), ["2", "3", "1"])
    }
}
