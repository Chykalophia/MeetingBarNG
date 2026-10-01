//
//  DropdownEventVisibility.swift
//  MeetingBarNG
//
//  Whether an event is shown in the dropdown at all, given the user's
//  hide/show settings.
//
//  Extracted from `DropdownPanelView` when the classic NSMenu was retired. It had
//  been a private method on the view, which meant the only way to test "choosing
//  hide for declined meetings actually hides them" was through the NSMenu's own
//  copy of the rule — so deleting the menu would have deleted the coverage for a
//  rule the panel still applies.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Foundation

enum DropdownEventVisibility {
    /// Whether the dropdown draws `event`.
    ///
    /// - Parameter now: injected so "finished" and "past" are decided against the
    ///   panel's ticking clock rather than a fresh `Date()` on every row.
    static func shouldRender(
        _ event: MBEvent,
        menu: MenuSettings,
        events: EventDisplaySettings,
        isDeclined: Bool,
        now: Date
    ) -> Bool {
        if menu.hideFinishedEventsInMenu,
           !EventListWindow.isVisible(endDate: event.endDate, now: now) {
            return false
        }
        if isDeclined, events.declinedEventsAppearance == .hide {
            return false
        }
        if event.endDate < now, events.pastEventsAppearance == .hide {
            return false
        }
        if event.attendees.isEmpty, events.personalEventsAppearance == .hide {
            return false
        }
        return true
    }

    /// The tomorrow events the agenda renders, before the row cap.
    ///
    /// The look-ahead setting decides how much of tomorrow is worth showing:
    /// all of it, just the first meeting, or — in summary mode — no rows at all,
    /// because that mode replaces them with a one-line count.
    /// The look-ahead mode is read from `display` rather than passed separately —
    /// it lives there, and taking both invited a caller to hand over two settings
    /// that disagreed.
    static func tomorrowRendered(
        _ events: [MBEvent],
        menu: MenuSettings,
        display: EventDisplaySettings,
        isDeclined: (MBEvent) -> Bool,
        now: Date
    ) -> [MBEvent] {
        let period = display.showEventsForPeriod
        guard period.includesTomorrow else { return [] }
        let visible = visible(
            events,
            menu: menu,
            display: display,
            isDeclined: isDeclined,
            now: now
        )
        switch period {
        case .today_n_tomorrow: return visible
        case .today_n_tomorrow_next: return Array(visible.prefix(1))
        default: return []
        }
    }

    /// The one-line summary that REPLACES tomorrow's rows in summary mode.
    ///
    /// The counterpart of `tomorrowRendered`, which returns no rows for that
    /// mode. Takes the full visible list, not the rendered one, because the point
    /// of the line is to count the meetings it is standing in for.
    static func tomorrowSummaryText(visibleTomorrowEvents events: [MBEvent]) -> String {
        let title = "status_bar_section_tomorrow".loco()
        guard !events.isEmpty else {
            return "status_bar_section_date_nothing".loco(title.lowercased())
        }
        // Manual `_one`/`_other` split, the same one the day-summary count uses —
        // without it a lone meeting reads "1 meetings tomorrow".
        let key = events.count == 1
            ? "status_bar_tomorrow_summary_one"
            : "status_bar_tomorrow_summary_other"
        return key.loco(
            events.count,
            events.first?.startDate.formatted(date: .omitted, time: .shortened) ?? ""
        )
    }

    /// The events the dropdown draws, in start order.
    static func visible(
        _ events: [MBEvent],
        menu: MenuSettings,
        display: EventDisplaySettings,
        isDeclined: (MBEvent) -> Bool,
        now: Date
    ) -> [MBEvent] {
        events
            .filter {
                shouldRender(
                    $0,
                    menu: menu,
                    events: display,
                    isDeclined: isDeclined($0),
                    now: now
                )
            }
            .sorted { $0.startDate < $1.startDate }
    }
}
