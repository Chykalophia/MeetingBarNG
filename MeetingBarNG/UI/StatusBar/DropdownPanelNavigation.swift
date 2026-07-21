//
//  DropdownPanelNavigation.swift
//  MeetingBarNG
//
//  Hostless keyboard-navigation model for the SwiftUI dropdown panel (Phase B of
//  the dropdown modernization). Pure value types + ordering/clamping math only —
//  no AppKit/SwiftUI/Defaults — so "Up/Down walks the interactive rows in visual
//  order and stops at the ends" is unit-testable without a UI test.
//
//  `DropdownPanelView` supplies a `DropdownPanelContent` describing what it is
//  about to render (the already-resolved module order plus the ids in each
//  module) and drives its selection highlight off the returned row list.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Foundation

/// One keyboard-reachable row of the dropdown panel, identified by what it acts
/// on rather than by index, so a selection survives a re-render that only
/// reorders neighbours.
enum DropdownPanelRow: Hashable {
    /// The next/current meeting summary card.
    case meetingSummary(String)
    /// The meeting module's repair/refresh row, shown instead of the card when
    /// there is no meeting to display.
    case emptyStateAction
    /// An agenda event row (today or tomorrow), by event id.
    case event(String)
    /// A reminder row, by reminder id.
    case reminder(String)
    /// The join module's "Join next/current meeting" row, by event id.
    case joinNext(String)
    /// The join module's "Create meeting" row.
    case createMeeting
    /// A bookmark row, by index into the stored bookmark list.
    case bookmark(Int)
    /// The pinned footer's "What's new?" row (only when the changelog is unread).
    case whatsNew
    case preferences
    case quit
}

/// Which way an arrow key moves the selection.
enum DropdownPanelMoveDirection {
    case up
    case down
}

/// A hostless description of what the panel is rendering: the resolved, visible
/// modules in order plus the identifiers inside each. Deliberately made of plain
/// strings/counts so the navigation math never needs `MBEvent`/`Defaults`.
struct DropdownPanelContent: Equatable {
    /// The visible modules, already resolved by `DropdownCompositionPolicy` and
    /// filtered to the ones with content.
    var modules: [DropdownModule] = []
    /// The event shown in the meeting-control card, when there is one.
    var meetingEventID: String?
    var todayEventIDs: [String] = []
    var reminderIDs: [String] = []
    var tomorrowEventIDs: [String] = []
    /// The event the join module's "Join …" row would join, when present.
    var joinNextEventID: String?
    var bookmarkCount: Int = 0
    /// Whether the pinned footer shows the "What's new?" row.
    var showsWhatsNew: Bool = false
}

enum DropdownPanelNavigation {
    /// The interactive rows the panel renders, in visual order: one pass over the
    /// resolved modules, then the pinned footer (which is never a module, so the
    /// user can always reach Preferences/Quit with the keyboard).
    static func interactiveRows(for content: DropdownPanelContent) -> [DropdownPanelRow] {
        var rows: [DropdownPanelRow] = []

        for module in content.modules {
            switch module {
            case .greeting, .timeline:
                // Presentation-only modules: nothing to select.
                continue
            case .meeting:
                rows.append(
                    content.meetingEventID.map(DropdownPanelRow.meetingSummary) ?? .emptyStateAction
                )
            case .agenda:
                rows += content.todayEventIDs.map(DropdownPanelRow.event)
                rows += content.reminderIDs.map(DropdownPanelRow.reminder)
                rows += content.tomorrowEventIDs.map(DropdownPanelRow.event)
            case .join:
                if let joinNextEventID = content.joinNextEventID {
                    rows.append(.joinNext(joinNextEventID))
                }
                rows.append(.createMeeting)
            case .bookmarks:
                rows += (0..<max(0, content.bookmarkCount)).map(DropdownPanelRow.bookmark)
            }
        }

        if content.showsWhatsNew { rows.append(.whatsNew) }
        rows.append(.preferences)
        rows.append(.quit)
        return rows
    }

    /// The selection index after one arrow-key step, clamped at both ends (a
    /// menu never wraps around). `nil` in, `nil` out only when there is nothing
    /// to select; otherwise a first press selects the first row going down and
    /// the last row going up. An out-of-range `current` (rows changed under the
    /// selection) snaps back into bounds.
    static func next(
        from current: Int?,
        direction: DropdownPanelMoveDirection,
        count: Int
    ) -> Int? {
        guard count > 0 else { return nil }
        guard let current else {
            return direction == .down ? 0 : count - 1
        }
        let clamped = min(max(current, 0), count - 1)
        guard clamped == current else { return clamped }
        let step = direction == .down ? 1 : -1
        return min(max(clamped + step, 0), count - 1)
    }
}
