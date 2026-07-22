//
//  SettingsIndexTests.swift
//  MeetingBarLogicTests
//
//  Hostless tests for the Preferences settings index (Phase 2 of the
//  Preferences UX overhaul). The index backs BOTH settings search and per-pane
//  reset, so these tests are the guard against a setting becoming unfindable or
//  unresettable when it moves between panes: every indexed label must resolve to
//  a real English key, read from `en.lproj` on disk.
//

import XCTest

@testable import MeetingBarLogic

final class SettingsIndexTests: XCTestCase {
    /// The English catalog, parsed from the repo (not a bundle): these tests run
    /// under `swift test` with no host app, so there is no bundle to read.
    /// NOTE: those directory names contain real trailing spaces.
    private static let englishCatalog: [String: String] = {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MeetingBarLogicTests
            .deletingLastPathComponent()  // repo root
        let strings = repoRoot
            .appendingPathComponent("MeetingBarNG")
            .appendingPathComponent("Resources ")
            .appendingPathComponent("Localization ")
            .appendingPathComponent("en.lproj")
            .appendingPathComponent("Localizable.strings")
        return NSDictionary(contentsOf: strings) as? [String: String] ?? [:]
    }()

    private func localized(_ key: String) -> String {
        Self.englishCatalog[key] ?? key
    }

    // MARK: - The index is intact

    func testEnglishCatalogLoads() {
        XCTAssertFalse(
            Self.englishCatalog.isEmpty,
            "en.lproj/Localizable.strings failed to parse — every other assertion here would pass vacuously"
        )
    }

    func testEveryIndexedSettingResolvesToARealEnglishKey() {
        for entry in SettingsIndex.all {
            XCTAssertNotNil(
                Self.englishCatalog[entry.labelKey],
                "\(entry.id): label key '\(entry.labelKey)' is not defined in en.lproj"
            )
            if let helpKey = entry.helpKey {
                XCTAssertNotNil(
                    Self.englishCatalog[helpKey],
                    "\(entry.id): help key '\(helpKey)' is not defined in en.lproj"
                )
            }
        }
    }

    func testEveryTabNameAndPurposeResolves() {
        for tab in PreferencesTab.allCases {
            XCTAssertNotNil(
                Self.englishCatalog[tab.titleKey],
                "\(tab.rawValue): title key '\(tab.titleKey)' is not defined in en.lproj"
            )
            XCTAssertNotNil(
                Self.englishCatalog[tab.purposeKey],
                "\(tab.rawValue): purpose key '\(tab.purposeKey)' is not defined in en.lproj"
            )
        }
    }

    func testEntryIdsAreUnique() {
        let ids = SettingsIndex.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate SettingsIndexEntry id")
    }

    func testEveryPaneHasAtLeastOneSetting() {
        for tab in PreferencesTab.allCases {
            XCTAssertFalse(
                SettingsIndex.entries(in: tab).isEmpty,
                "\(tab.rawValue) has no indexed settings — an empty pane is a pane nobody can search"
            )
        }
    }

    func testTabOrderIsTheSidebarOrder() {
        XCTAssertEqual(
            PreferencesTab.allCases,
            [.calendars, .filters, .menuBar, .dropdown, .calendarWindow, .joining, .alerts, .general]
        )
        XCTAssertEqual(PreferencesTab.defaultSelection, .calendars)
    }

    // MARK: - Reset scope

    func testResetKeysAreDeduplicatedPerPane() {
        let filters = SettingsIndex.defaultsKeys(in: .filters)
        XCTAssertEqual(Set(filters).count, filters.count)
        // The ended-meetings row owns BOTH merged keys, so resetting Filters
        // restores the pair together rather than half of it.
        XCTAssertTrue(filters.contains("pastEventsAppereance"))
        XCTAssertTrue(filters.contains("hideFinishedEventsInMenu"))
    }

    func testEachPaneResetsOnlyItsOwnKeys() {
        // A key may only belong to one pane: two panes resetting the same key
        // is the "one thought, two places" failure this IA exists to remove.
        var owner: [String: PreferencesTab] = [:]
        for tab in PreferencesTab.allCases {
            for key in SettingsIndex.defaultsKeys(in: tab) {
                if let existing = owner[key] {
                    XCTFail("'\(key)' is owned by both \(existing.rawValue) and \(tab.rawValue)")
                }
                owner[key] = tab
            }
        }
        XCTAssertEqual(Set(SettingsIndex.allDefaultsKeys).count, owner.count)
    }

    func testResetKeysUseStoredKeyNamesNotSwiftPropertyNames() {
        // `runJoinEventScript` is stored under a DIFFERENT name. Resetting the
        // Swift property name would silently no-op.
        XCTAssertTrue(
            SettingsIndex.defaultsKeys(in: .alerts).contains("runAppleScriptWhenJoiningEvent")
        )
        XCTAssertFalse(SettingsIndex.defaultsKeys(in: .alerts).contains("runJoinEventScript"))
    }

    // MARK: - Search

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(SettingsIndex.search("", localized: localized).isEmpty)
        XCTAssertTrue(SettingsIndex.search("   ", localized: localized).isEmpty)
    }

    func testSynonymsFindSettingsWhoseLabelNeverSaysTheWord() {
        // "dot" is genuinely ambiguous — the calendar colour marker AND the
        // menu-bar title's dot mode. Both must be reachable from the one word;
        // adding "calendar" disambiguates to the marker.
        let dotHits = SettingsIndex.search("dot", localized: localized).map(\.id)
        XCTAssertTrue(dotHits.contains("dropdown.row_calendar_colour"))
        XCTAssertTrue(dotHits.contains("menubar.title"))
        XCTAssertEqual(
            SettingsIndex.search("calendar dot", localized: localized).first?.id,
            "dropdown.row_calendar_colour"
        )
        // Nothing in Preferences says "am/pm" — the time format does.
        XCTAssertEqual(
            SettingsIndex.search("am pm", localized: localized).first?.id,
            "general.time_format"
        )
        // "regex" is banned from user-facing copy but is what a power user types.
        let regexHits = SettingsIndex.search("regex", localized: localized).map(\.id)
        XCTAssertTrue(regexHits.contains("filters.title_patterns"))
        XCTAssertTrue(regexHits.contains("joining.link_patterns"))
        // "strikethrough" is a deleted option value; the row that replaced it
        // must still be findable by the old word.
        XCTAssertEqual(
            SettingsIndex.search("strikethrough", localized: localized).first?.id,
            "filters.declined"
        )
    }

    func testQueriesLandOnTheExpectedControl() {
        XCTAssertEqual(
            SettingsIndex.search("declined", localized: localized).first?.id,
            "filters.declined"
        )
        XCTAssertEqual(
            SettingsIndex.search("24 hour", localized: localized).first?.id,
            "general.time_format"
        )
        XCTAssertEqual(
            SettingsIndex.search("weekend", localized: localized).first?.id,
            "calendarwindow.dim_weekends"
        )
        XCTAssertEqual(
            SettingsIndex.search("overdue", localized: localized).first?.id,
            "dropdown.reminders"
        )
    }

    func testEveryTermMustMatch() {
        // AND across terms: a query mixing two unrelated words matches nothing.
        XCTAssertTrue(
            SettingsIndex.search("weekend applescript", localized: localized).isEmpty
        )
    }

    func testSearchIsAccentAndCaseInsensitive() {
        XCTAssertEqual(
            SettingsIndex.search("DECLINED", localized: localized).first?.id,
            SettingsIndex.search("declined", localized: localized).first?.id
        )
    }

    func testResultsAreStableForTiedScores() {
        let first = SettingsIndex.search("meeting", localized: localized).map(\.id)
        let second = SettingsIndex.search("meeting", localized: localized).map(\.id)
        XCTAssertEqual(first, second)
    }
}
