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

        XCTAssertEqual(groups.map(\.account), ["Google", "iCloud"])
        XCTAssertEqual(groups[0].rows.map(\.id), ["2"])
        XCTAssertEqual(groups[1].rows.map(\.id), ["3", "1"])
    }

    func testUnknownSourceRendersAsOtherAndSortsLast() {
        let groups = CalendarListPresentation.groups(for: [
            item("1", "Odd one", source: CalendarListPresentation.unknownSource),
            item("2", "Work", source: "iCloud")
        ])

        XCTAssertEqual(groups.map(\.account), ["iCloud", CalendarListPresentation.unknownSource])
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
        XCTAssertEqual(groups[0].account, "iCloud")
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

    // MARK: - Telling the two sources apart
    //
    // THE REGRESSION THIS BLOCK EXISTS FOR. With both sources connected the
    // settings list showed the usual calendars with no way to tell which came
    // from the Mac and which from the direct Google connection — and macOS
    // reports a Google account as a source literally NAMED "Google", so the
    // account name alone could not answer it.

    func test_sameAccountNameFromBothSourcesStaysTwoGroups() {
        let groups = CalendarListPresentation.groups(for: [
            CalendarPickerItem(
                id: "ek", title: "Work", source: "Google", email: "p@example.com",
                provider: .macOSEventKit),
            CalendarPickerItem(
                id: "g", title: "Work", source: "Google", email: "p@example.com",
                provider: .googleCalendar)
        ])

        XCTAssertEqual(groups.count, 2, "one group per source, not one merged group")
        XCTAssertEqual(groups.map(\.provider), [.macOSEventKit, .googleCalendar])
        XCTAssertEqual(
            Set(groups.map(\.id).map { $0 }).count, 2,
            "group identity must stay unique or SwiftUI would collapse the sections")
    }

    func test_eachGroupNamesItsSource() {
        let groups = CalendarListPresentation.groups(for: [
            CalendarPickerItem(
                id: "ek", title: "Home", source: "iCloud", email: nil,
                provider: .macOSEventKit),
            CalendarPickerItem(
                id: "g", title: "Team", source: "p@example.com", email: "p@example.com",
                provider: .googleCalendar)
        ])

        XCTAssertEqual(
            groups.map(\.providerTitleKey),
            ["onboarding_apple_calendar_title", "onboarding_google_calendar_title"]
        )
    }

    /// Each source's accounts stay contiguous, in the canonical source order —
    /// "everything my Mac syncs", then "everything Google sends". Interleaving
    /// them alphabetically would put the answer to "where is this from" in a
    /// different place for every row.
    func test_accountsAreGroupedBySourceInDisplayOrder() {
        let groups = CalendarListPresentation.groups(for: [
            CalendarPickerItem(
                id: "g", title: "Team", source: "aaa@example.com", email: nil,
                provider: .googleCalendar),
            CalendarPickerItem(
                id: "ek2", title: "Home", source: "zzz-iCloud", email: nil,
                provider: .macOSEventKit),
            CalendarPickerItem(
                id: "ek1", title: "Work", source: "mmm-Exchange", email: nil,
                provider: .macOSEventKit)
        ])

        XCTAssertEqual(
            groups.map(\.provider),
            [.macOSEventKit, .macOSEventKit, .googleCalendar],
            "sorting by account name alone would have put the Google group first")
        XCTAssertEqual(groups.map(\.account), ["mmm-Exchange", "zzz-iCloud", "aaa@example.com"])
    }

    /// A calendar named the same on both sources still gets its address shown,
    /// because ambiguity is counted across the whole list.
    func test_duplicateNameAcrossSourcesKeepsTheDisambiguator() {
        let groups = CalendarListPresentation.groups(for: [
            CalendarPickerItem(
                id: "ek", title: "Work", source: "iCloud", email: "me@icloud.com",
                provider: .macOSEventKit),
            CalendarPickerItem(
                id: "g", title: "Work", source: "p@example.com", email: "p@example.com",
                provider: .googleCalendar)
        ])

        XCTAssertEqual(groups.flatMap { $0.rows }.compactMap(\.subtitle).count, 2)
    }
}
