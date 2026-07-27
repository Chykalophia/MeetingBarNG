//
//  MoreActionsMenuTests.swift
//  MeetingBarNG
//
//  Characterization tests for the dropdown panel's "More actions" flyout.
//
//  The panel is a custom NSWindow rather than an NSMenu, so its More-actions row
//  is a SwiftUI view and the flyout is assembled by hand in
//  `DropdownPanelView.makeMoreActionsMenu()`. Which entries appear is decided by
//  plain conditionals — next meeting present, dismissals present, menu bar
//  currently showing a title — and nothing else in either suite touches this
//  file. `MeetingBarLogicTests` cannot: it is a hostless SPM module with no view
//  of the app target.
//
//  These pin the emitted item sequence, separators included, so a later edit to
//  those conditionals cannot silently drop, duplicate or reorder an action, and
//  cannot leave a stray separator behind when the group above it is empty.
//
//  Created for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import AppKit
import XCTest

@testable import MeetingBarNG

@MainActor
final class MoreActionsMenuTests: BaseTestCase {
    /// Fixed so "dismiss NEXT" vs "dismiss CURRENT" never depends on wall clock.
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func makeMenu(
        nextEvent: MBEvent? = nil,
        dismissed: [ProcessedEvent] = [],
        titleFormat: EventTitleFormat = .dot
    ) -> NSMenu {
        var settings = AppSettings.empty
        settings.events.dismissedEvents = dismissed
        settings.statusBar.eventTitleFormat = titleFormat

        var state = StatusBarMenuState()
        state.settings = settings
        state.nextEvent = nextEvent

        return DropdownPanelView(
            state: state,
            handlers: DropdownPanelHandlers(),
            now: now
        ).makeMoreActionsMenu()
    }

    /// Separators are rendered as a literal so their PLACEMENT is pinned too — a
    /// leading separator with nothing above it is the specific bug this catches.
    private func titles(of menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "---" : $0.title }
    }

    private func futureEvent() -> MBEvent {
        makeFakeEvent(
            id: "next",
            start: now.addingTimeInterval(600),
            end: now.addingTimeInterval(3600),
            withLink: true
        )
    }

    private func dismissal() -> ProcessedEvent {
        ProcessedEvent(id: "dismissed", eventEndDate: now.addingTimeInterval(3600))
    }

    /// Everything that is always present, in order.
    private var alwaysOn: [String] {
        [
            "status_bar_section_join_from_clipboard".loco(),
            "---",
            "status_bar_quick_action_camera_check".loco(),
            "status_bar_quick_action_world_clock".loco(),
            "---",
            "status_bar_section_refresh_sources".loco()
        ]
    }

    // MARK: - The four combinations of the leading, conditional group

    func testNoNextMeetingAndNoDismissalsOmitsTheLeadingGroupEntirely() {
        // Nothing to dismiss and nothing dismissed: no items AND no separator.
        XCTAssertEqual(titles(of: makeMenu()), alwaysOn)
    }

    func testNextMeetingAddsDismissFollowedByItsSeparator() {
        let menu = makeMenu(nextEvent: futureEvent())
        XCTAssertEqual(
            titles(of: menu),
            ["status_bar_menu_dismiss_next_meeting".loco(), "---"] + alwaysOn
        )
    }

    func testDismissalsAloneAddUndismissFollowedByItsSeparator() {
        let menu = makeMenu(dismissed: [dismissal()])
        XCTAssertEqual(
            titles(of: menu),
            ["status_bar_menu_remove_all_dismissals".loco(), "---"] + alwaysOn
        )
    }

    func testNextMeetingAndDismissalsAddBothWithOneSeparator() {
        let menu = makeMenu(nextEvent: futureEvent(), dismissed: [dismissal()])
        XCTAssertEqual(
            titles(of: menu),
            [
                "status_bar_menu_dismiss_next_meeting".loco(),
                "status_bar_menu_remove_all_dismissals".loco(),
                "---"
            ] + alwaysOn
        )
    }

    // MARK: - Dismiss row wording

    func testDismissRowSaysCurrentOnceTheMeetingHasStarted() {
        let started = makeFakeEvent(
            id: "running",
            start: now.addingTimeInterval(-300),
            end: now.addingTimeInterval(1800),
            withLink: true
        )
        XCTAssertEqual(
            titles(of: makeMenu(nextEvent: started)).first,
            "status_bar_menu_dismiss_curent_meeting".loco()
        )
    }

    // MARK: - Meeting-title visibility gating

    func testTitleVisibilityRowIsAbsentWhenTheMenuBarShowsNoTitle() {
        for format in [EventTitleFormat.dot, .none] {
            let titles = titles(of: makeMenu(titleFormat: format))
            XCTAssertEqual(titles, alwaysOn, "unexpected extra row for \(format)")
        }
    }

    func testTitleVisibilityRowOffersToHideWhenTitlesAreShown() {
        let titles = titles(of: makeMenu(titleFormat: .show))
        XCTAssertTrue(
            titles.contains("status_bar_hide_meeting_names".loco()),
            "expected a hide-names row, got \(titles)"
        )
    }

    func testTitleVisibilityRowOffersToShowWhenTitlesAreGeneric() {
        let titles = titles(of: makeMenu(titleFormat: .generic))
        XCTAssertTrue(
            titles.contains("status_bar_show_meeting_names".loco()),
            "expected a show-names row, got \(titles)"
        )
    }

    func testTitleVisibilityRowSitsDirectlyBelowTheClipboardRow() {
        let titles = titles(of: makeMenu(titleFormat: .show))
        guard let clipboard = titles.firstIndex(of: "status_bar_section_join_from_clipboard".loco()) else {
            return XCTFail("clipboard row missing from \(titles)")
        }
        XCTAssertEqual(titles[clipboard + 1], "status_bar_hide_meeting_names".loco())
    }

    // MARK: - Enablement

    /// `autoenablesItems` is off, so anything that forgot to set `isEnabled`
    /// would render permanently greyed out.
    func testEveryActionableItemIsEnabledAndCarriesAnAction() {
        let menu = makeMenu(
            nextEvent: futureEvent(),
            dismissed: [dismissal()],
            titleFormat: .show
        )
        XCTAssertFalse(menu.autoenablesItems)
        for item in menu.items where !item.isSeparatorItem {
            XCTAssertTrue(item.isEnabled, "\(item.title) is disabled")
            XCTAssertNotNil(item.action, "\(item.title) has no action")
            XCTAssertNotNil(item.target, "\(item.title) has no target")
        }
    }

    /// Every non-separator row must be a real, distinct action — a duplicated
    /// title means a conditional emitted the same entry twice.
    func testNoDuplicateRows() {
        let titles = titles(of: makeMenu(
            nextEvent: futureEvent(),
            dismissed: [dismissal()],
            titleFormat: .show
        )).filter { $0 != "---" }
        XCTAssertEqual(Set(titles).count, titles.count, "duplicate rows in \(titles)")
    }

    /// A separator must never lead, trail, or sit next to another one.
    func testSeparatorsNeverStrandThemselves() {
        let combinations: [(MBEvent?, [ProcessedEvent], EventTitleFormat)] = [
            (nil, [], .dot),
            (futureEvent(), [], .dot),
            (nil, [dismissal()], .dot),
            (futureEvent(), [dismissal()], .show)
        ]
        for (event, dismissed, format) in combinations {
            let titles = titles(of: makeMenu(
                nextEvent: event,
                dismissed: dismissed,
                titleFormat: format
            ))
            XCTAssertNotEqual(titles.first, "---", "leading separator in \(titles)")
            XCTAssertNotEqual(titles.last, "---", "trailing separator in \(titles)")
            for (index, title) in titles.enumerated() where title == "---" && index > 0 {
                XCTAssertNotEqual(titles[index - 1], "---", "double separator in \(titles)")
            }
        }
    }
}
