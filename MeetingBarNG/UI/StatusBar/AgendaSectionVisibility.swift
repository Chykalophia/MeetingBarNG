//
//  AgendaSectionVisibility.swift
//  MeetingBarNG
//
//  Whether an agenda DAY SECTION is drawn at all — distinct from
//  `DropdownEventVisibility`, which decides whether an individual event is drawn.
//  A day can be legitimately empty because every event in it was filtered out,
//  so the two questions have to be answered in that order.
//
//  Hostless: counts and flags only, no MBEvent, so "hide empty days actually
//  hides them, and never hides today" is a unit test rather than a thing you
//  check by emptying your calendar.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Foundation

public enum AgendaSectionVisibilityPolicy {
    /// Whether to draw a day's section — its heading, its separator, and its
    /// empty-state line.
    ///
    /// **The anchor day is never hidden.** With today empty and hiding on, the
    /// panel would otherwise render an agenda with no headings at all, which
    /// reads as a broken panel rather than a free day. "Nothing today" is also
    /// the single most useful thing the agenda can tell you, so it is worth its
    /// two rows. The setting therefore only ever suppresses the look-ahead day,
    /// where an empty section is pure overhead.
    ///
    /// - Parameters:
    ///   - eventCount: events the section would draw AFTER per-event filtering.
    ///     Callers must pass the rendered count, not the raw one, or a day whose
    ///     every meeting was hidden as declined still occupies space.
    ///   - isIncludedByPeriod: whether the user's look-ahead setting covers this
    ///     day at all. Decided first — a day outside the period is not "empty".
    ///   - hidesEmptyDays: the user's preference.
    ///   - isAnchorDay: today. See above.
    public static func showsSection(
        eventCount: Int,
        isIncludedByPeriod: Bool,
        hidesEmptyDays: Bool,
        isAnchorDay: Bool
    ) -> Bool {
        guard isIncludedByPeriod else { return false }
        if isAnchorDay { return true }
        guard hidesEmptyDays else { return true }
        return eventCount > 0
    }
}
