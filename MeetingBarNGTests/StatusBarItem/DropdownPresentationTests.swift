//
//  DropdownPresentationTests.swift
//  MeetingBarNGTests
//
//  Covers the three types pulled out of `MenuBuilder` when the classic NSMenu was
//  retired: the meeting card's copy, the right-click quick actions, and the
//  agenda's visibility rules. Each was previously reachable only through the
//  menu, so without these the deletion would have taken the coverage with it.
//

import Defaults
import XCTest
@testable import MeetingBarNG

final class MeetingSummaryPresenterTests: BaseTestCase {
    private func makeEvent(
        id: String = "E1",
        title: String = "Standup",
        startsIn: TimeInterval = 300,
        lasts: TimeInterval = 1800,
        calendar: MBCalendar? = nil,
        organizerEmail: String? = nil,
        now: Date
    ) -> MBEvent {
        MBEvent(
            id: id,
            lastModifiedDate: now,
            title: title,
            status: .confirmed,
            notes: nil,
            location: nil,
            url: URL(string: "https://zoom.us/j/5551112222"),
            organizer: organizerEmail.map { MBEventOrganizer(email: $0, name: $0) },
            startDate: now.addingTimeInterval(startsIn),
            endDate: now.addingTimeInterval(startsIn + lasts),
            isAllDay: false,
            recurrent: false,
            calendar: calendar ?? MBCalendar(
                title: "Work",
                id: "cal",
                source: nil,
                email: nil,
                color: .black
            )
        )
    }

    /// The same account arrives from calendar email, source and organizer; the
    /// metadata line must not say it three times.
    func testMetadataDeduplicatesAccountCalendarAndOrganizer() {
        let now = Date()
        let duplicate = "same@example.com"
        let event = makeEvent(
            calendar: MBCalendar(
                title: duplicate,
                id: "duplicate-metadata",
                source: duplicate,
                email: duplicate,
                color: .black
            ),
            organizerEmail: duplicate,
            now: now
        )

        let presentation = MeetingSummaryPresenter.presentation(
            for: event,
            timeFormat: .am_pm,
            now: now
        )

        XCTAssertEqual(presentation.metadata.filter { $0 == duplicate }.count, 1)
        XCTAssertTrue(presentation.metadata.contains("Zoom"))
    }

    func testSectionTitleSaysNextBeforeTheMeetingAndCurrentDuringIt() {
        let now = Date()
        let upcoming = MeetingSummaryPresenter.presentation(
            for: makeEvent(startsIn: 300, now: now),
            timeFormat: .am_pm,
            now: now
        )
        XCTAssertEqual(upcoming.sectionTitle, "status_bar_control_next_meeting".loco())

        let running = MeetingSummaryPresenter.presentation(
            for: makeEvent(startsIn: -300, now: now),
            timeFormat: .am_pm,
            now: now
        )
        XCTAssertEqual(running.sectionTitle, "status_bar_control_current_meeting".loco())
    }

    /// A running meeting has no "in 5m" to show; an upcoming one does.
    func testCountdownOnlyAppearsBeforeTheMeetingStarts() {
        let now = Date()
        XCTAssertNotNil(
            MeetingSummaryPresenter.presentation(
                for: makeEvent(startsIn: 300, now: now),
                timeFormat: .am_pm,
                now: now
            ).countdown
        )
        XCTAssertNil(
            MeetingSummaryPresenter.presentation(
                for: makeEvent(startsIn: -300, now: now),
                timeFormat: .am_pm,
                now: now
            ).countdown
        )
    }

    /// The card shows the real title even when the MENU BAR is set to hide it —
    /// the privacy setting is about the always-visible strip, not the dropdown
    /// the user deliberately opened.
    func testTitleIsKeptWhenTheStatusBarUsesAGenericTitle() {
        let now = Date()
        let event = makeEvent(title: "Board review", now: now)
        Defaults[.eventTitleFormat] = .generic

        let presentation = MeetingSummaryPresenter.presentation(
            for: event,
            timeFormat: .am_pm,
            now: now
        )
        XCTAssertEqual(presentation.eventTitle, "Board review")
    }

    func testTimeStringsFollowTheChosenFormat() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let event = makeEvent(now: now)

        let twelve = MeetingSummaryPresenter.timeStrings(for: event, timeFormat: .am_pm)
        let twentyFour = MeetingSummaryPresenter.timeStrings(for: event, timeFormat: .military)

        XCTAssertNotEqual(twelve.start, twentyFour.start)
        XCTAssertFalse(twelve.start.isEmpty)
        XCTAssertFalse(twentyFour.start.isEmpty)
    }
}

@MainActor
final class QuickActionsMenuTests: BaseTestCase {
    private final class Target: NSObject {}

    /// Join is only actionable when there is something to join.
    func testJoinIsDisabledWithoutAMeetingLink() {
        var state = StatusBarMenuState()
        state.settings = .empty

        let menu = QuickActionsMenu.build(target: Target(), state: state)
        let join = menu.items.first {
            $0.action == #selector(StatusBarItemController.joinNextMeeting)
        }
        XCTAssertNotNil(join)
        XCTAssertFalse(join?.isEnabled ?? true)
    }

    /// In-app event creation is EventKit-only, so the entry hides for Google.
    func testNewEventOnlyAppearsForTheEventKitProvider() {
        var eventKit = StatusBarMenuState()
        eventKit.settings = .empty
        eventKit.activeProvider = .macOSEventKit

        var google = StatusBarMenuState()
        google.settings = .empty
        google.activeProvider = .googleCalendar

        let newEvent = #selector(StatusBarItemController.newEventAction)
        XCTAssertTrue(
            QuickActionsMenu.build(target: Target(), state: eventKit)
                .items.contains { $0.action == newEvent }
        )
        XCTAssertFalse(
            QuickActionsMenu.build(target: Target(), state: google)
                .items.contains { $0.action == newEvent }
        )
    }

    func testEveryActionableItemTargetsTheController() {
        var state = StatusBarMenuState()
        state.settings = .empty
        let target = Target()

        for item in QuickActionsMenu.build(target: target, state: state).items
        where !item.isSeparatorItem {
            XCTAssertNotNil(item.action, "\(item.title) has no action")
            XCTAssertTrue(item.target === target, "\(item.title) points elsewhere")
        }
    }
}

final class DropdownEventVisibilityTests: BaseTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(
        id: String,
        startsIn: TimeInterval,
        lasts: TimeInterval = 1800,
        attendees: [MBEventAttendee] = []
    ) -> MBEvent {
        var made = makeFakeEvent(
            id: id,
            start: now.addingTimeInterval(startsIn),
            end: now.addingTimeInterval(startsIn + lasts)
        )
        made.attendees = attendees
        return made
    }

    private func settings(
        hideFinished: Bool = false,
        past: PastEventsAppereance = .show_active,
        personal: PastEventsAppereance = .show_active,
        declined: DeclinedEventsAppereance = .strikethrough
    ) -> (MenuSettings, EventDisplaySettings) {
        var all = AppSettings.empty
        all.menu.hideFinishedEventsInMenu = hideFinished
        all.events.pastEventsAppearance = past
        all.events.personalEventsAppearance = personal
        all.events.declinedEventsAppearance = declined
        return (all.menu, all.events)
    }

    func testPastEventsAreHiddenOnlyWhenTheSettingSaysSo() {
        let past = event(id: "PAST", startsIn: -7200)

        let (shownMenu, shownEvents) = settings(past: .show_active)
        XCTAssertTrue(
            DropdownEventVisibility.shouldRender(
                past, menu: shownMenu, events: shownEvents, isDeclined: false, now: now
            )
        )

        let (hiddenMenu, hiddenEvents) = settings(past: .hide)
        XCTAssertFalse(
            DropdownEventVisibility.shouldRender(
                past, menu: hiddenMenu, events: hiddenEvents, isDeclined: false, now: now
            )
        )
    }

    func testDeclinedEventsAreHiddenOnlyWhenTheSettingSaysSo() {
        let upcoming = event(id: "DECLINED", startsIn: 300)
        let (menu, events) = settings(declined: .hide)

        XCTAssertFalse(
            DropdownEventVisibility.shouldRender(
                upcoming, menu: menu, events: events, isDeclined: true, now: now
            )
        )
        XCTAssertTrue(
            DropdownEventVisibility.shouldRender(
                upcoming, menu: menu, events: events, isDeclined: false, now: now
            )
        )
    }

    /// "Personal" means nobody else is invited.
    func testPersonalEventsAreHiddenOnlyWhenTheSettingSaysSo() {
        let alone = event(id: "SOLO", startsIn: 300, attendees: [])
        let (menu, events) = settings(personal: .hide)

        XCTAssertFalse(
            DropdownEventVisibility.shouldRender(
                alone, menu: menu, events: events, isDeclined: false, now: now
            )
        )
    }

    func testVisibleSortsByStart() {
        let (menu, events) = settings()
        let sorted = DropdownEventVisibility.visible(
            [event(id: "LATE", startsIn: 3600), event(id: "SOON", startsIn: 300)],
            menu: menu,
            display: events,
            isDeclined: { _ in false },
            now: now
        )
        XCTAssertEqual(sorted.map(\.id), ["SOON", "LATE"])
    }

    func testTomorrowModesDecideHowMuchOfTomorrowRenders() {
        let (menu, events) = settings()
        let tomorrow = [event(id: "A", startsIn: 86_400), event(id: "B", startsIn: 90_000)]

        func rendered(_ period: ShowEventsForPeriod) -> [String] {
            DropdownEventVisibility.tomorrowRendered(
                tomorrow,
                period: period,
                menu: menu,
                display: events,
                isDeclined: { _ in false },
                now: now
            ).map(\.id)
        }

        XCTAssertEqual(rendered(.today), [], "today-only shows none of tomorrow")
        XCTAssertEqual(rendered(.today_n_tomorrow), ["A", "B"])
        XCTAssertEqual(rendered(.today_n_tomorrow_next), ["A"])
        XCTAssertEqual(
            rendered(.today_n_tomorrow_summary), [],
            "summary mode replaces the rows with a line, so it renders none"
        )
    }

    /// A lone meeting must not read "1 meetings tomorrow".
    func testSummaryLinePicksSingularAndPlural() {
        let one = DropdownEventVisibility.tomorrowSummaryText(
            visibleTomorrowEvents: [event(id: "A", startsIn: 86_400)]
        )
        let two = DropdownEventVisibility.tomorrowSummaryText(
            visibleTomorrowEvents: [
                event(id: "A", startsIn: 86_400),
                event(id: "B", startsIn: 90_000)
            ]
        )
        XCTAssertNotEqual(one, two)
        XCTAssertFalse(one.isEmpty)
    }

    func testSummaryLineSaysNothingWhenTomorrowIsEmpty() {
        XCTAssertEqual(
            DropdownEventVisibility.tomorrowSummaryText(visibleTomorrowEvents: []),
            "status_bar_section_date_nothing".loco(
                "status_bar_section_tomorrow".loco().lowercased()
            )
        )
    }
}
