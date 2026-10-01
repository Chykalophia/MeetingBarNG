//
//  CalendarGridNavigation.swift
//  MeetingBarNG
//
//  Arrow-key travel across a calendar grid: where the selection lands, and
//  whether the grid has to page to keep it visible.
//
//  Hostless, because "walking off the end of a month pages to the next one" is
//  the part that is easy to get subtly wrong and impossible to notice in a
//  screenshot. The view maps key presses to a day delta; everything after that
//  is here.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Foundation

/// Where a move landed, and what the grid must do about it.
public struct CalendarGridNavigationResult: Equatable, Sendable {
    /// The newly selected day, normalised to the start of that day.
    public let selectedDay: Date
    /// Whether the selection left the range currently on screen, so the caller
    /// must re-anchor. The caller decides HOW to page — this only reports that
    /// it must, because the anchor differs between month and week mode.
    public let requiresPaging: Bool

    public init(selectedDay: Date, requiresPaging: Bool) {
        self.selectedDay = selectedDay
        self.requiresPaging = requiresPaging
    }
}

public enum CalendarGridNavigation {
    /// Day deltas for the four arrow keys.
    ///
    /// Left/right are ±1 day and up/down are ±7, which is the grid's own
    /// geometry: a row IS a week, so Up must land in the cell directly above.
    /// Anything else makes the keyboard disagree with what the eye sees.
    public static let previousDay = -1
    public static let nextDay = 1
    public static let previousWeek = -7
    public static let nextWeek = 7

    /// Moves the selection by `days`, reporting whether the grid must re-anchor.
    ///
    /// - Parameters:
    ///   - selectedDay: the current selection. Callers with no selection should
    ///     pass the day the grid is anchored on, so the first arrow press starts
    ///     somewhere visible rather than at an arbitrary date.
    ///   - visibleRange: the inclusive first and last day currently drawn — for a
    ///     month grid that INCLUDES the padding days from the adjacent months,
    ///     since those cells are on screen and selecting one should not page.
    public static func move(
        from selectedDay: Date,
        byDays days: Int,
        visibleRange: (start: Date, end: Date),
        calendar: Calendar
    ) -> CalendarGridNavigationResult {
        let current = calendar.startOfDay(for: selectedDay)
        guard let moved = calendar.date(byAdding: .day, value: days, to: current) else {
            return CalendarGridNavigationResult(selectedDay: current, requiresPaging: false)
        }
        let landed = calendar.startOfDay(for: moved)

        let first = calendar.startOfDay(for: visibleRange.start)
        let last = calendar.startOfDay(for: visibleRange.end)
        // Inclusive on both ends: the last drawn day is on screen, and paging
        // when the user selects it would scroll the grid out from under them.
        let isVisible = landed >= first && landed <= last

        return CalendarGridNavigationResult(selectedDay: landed, requiresPaging: !isVisible)
    }
}
