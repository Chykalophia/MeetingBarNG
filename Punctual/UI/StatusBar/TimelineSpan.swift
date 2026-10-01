//
//  TimelineSpan.swift
//  MeetingBarNG
//
//  How the dropdown's timeline bar frames time. Hostless: the range is pure date
//  arithmetic, so "the bar always opens on content" is a unit test rather than
//  something you judge by squinting at a screenshot.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Foundation

/// What span the timeline draws, or whether it draws at all.
///
/// `off` lives HERE rather than as a separate `showTimelineInMenu` toggle. Two
/// controls for one thing is how they end up disagreeing — a user could switch
/// the style of a timeline that was hidden, or hide one whose style they had
/// just set. One picker answers both questions.
public enum TimelineSpan: String, CaseIterable, Codable, Hashable, Sendable {
    /// Not drawn.
    case off
    /// A window around now. Reads as "what is near me", and the marker moves
    /// across it as the day passes.
    case relative
    /// The working day end to end. Reads as "where am I in the day", and every
    /// meeting has a fixed place on the bar all day long.
    case day

    public var isVisible: Bool { self != .off }
}

/// Carries two retired controls onto the ones that replaced them.
///
/// The dropdown had an `upNext` module drawing a second card for the meeting the
/// `meeting` module already showed, and a `showTimelineInMenu` toggle beside a
/// timeline STYLE picker. Both were two controls for one thing. Hostless so the
/// decisions are tested; the Defaults plumbing lives in
/// `DropdownModuleMergeMigration`.
/// How the timeline is DRAWN. Orthogonal to `TimelineSpan`, which says what
/// stretch of time it covers.
///
/// The two were briefly conflated — a picker labelled "Draw the timeline as"
/// offered Around now / Whole day, which are spans. You can want a compact bar
/// showing the whole day, or a detailed track around now, and every combination
/// in between is meaningful.
public enum TimelineAppearance: String, CaseIterable, Codable, Hashable, Sendable {
    /// Hour grid, labels above, meetings as capsules packed into as many rows as
    /// overlaps require. The most informative and the tallest — the only one that
    /// shows two meetings clashing.
    case track
    /// One rail with the meetings inline and the hours labelled beneath it.
    /// Roughly half the height of `track`; loses overlap, keeps duration.
    case bar
    /// The rail alone, no labels. A glance at shape and position, nothing more.
    case minimal

    /// Whether hour labels are drawn, and where relative to the track.
    public var showsHourLabels: Bool { self != .minimal }

    /// `track` stacks overlapping meetings; the others flatten them onto one line.
    public var stacksOverlaps: Bool { self == .track }
}

public enum DropdownModuleMergePolicy {
    /// The countdown bar is on if the user had the up-next card.
    public static func showsProgress(hadUpNextModule: Bool) -> Bool { hadUpNextModule }

    /// A hidden timeline stays hidden; a shown one keeps the stored style, since
    /// there was no style to preserve before this.
    public static func timelineStyle(
        wasVisible: Bool,
        stored: TimelineSpan
    ) -> TimelineSpan {
        wasVisible ? stored : .off
    }
}

public enum DayTimelineRange {
    /// Window ahead of and behind `now` for `.relative`.
    public static let relativeLookBehind: TimeInterval = 3 * 3600
    public static let relativeLookAhead: TimeInterval = 6 * 3600

    /// The narrowest the relative window is allowed to get once it is pulled in
    /// around real events. Below this the bar stops being a timeline and starts
    /// being a progress bar for one meeting.
    public static let minimumRelativeSpan: TimeInterval = 4 * 3600

    /// Past and future the relative window always shows, whatever the day holds.
    ///
    /// The look-BEHIND is why the marker is never flush against the leading edge:
    /// pulling the window tight to the next meeting technically removes the dead
    /// space, but it also pins "now" to the very start of the bar, which reads as
    /// clipped rather than as current. An hour of context is enough to place it.
    public static let minimumLookBehind: TimeInterval = 3600
    public static let minimumLookAhead: TimeInterval = 2 * 3600

    /// Hours the `.day` style covers when the day holds nothing unusual.
    public static let dayStartHour = 8
    public static let dayEndHour = 20

    /// The span the bar draws.
    ///
    /// - Parameter bounds: the earliest start and latest end among the events
    ///   being drawn, or `nil` when there are none.
    public static func range(
        style: TimelineSpan,
        now: Date,
        bounds: (first: Date, last: Date)?,
        calendar: Calendar = .current
    ) -> ClosedRange<Date> {
        switch style {
        // `.off` draws nothing, so its range is never read; answering with the
        // relative window keeps this total without a fatalError in a pure
        // function.
        case .off, .relative: relativeRange(now: now, bounds: bounds)
        case .day: dayRange(now: now, bounds: bounds, calendar: calendar)
        }
    }

    /// A window around now that always opens on something.
    ///
    /// The fixed −3h/+6h window left the bar starting in dead space: at 4pm with
    /// nothing before 7pm, the left THIRD was empty past, which reads as a broken
    /// layout rather than as "the morning is behind you". The window is now
    /// pulled in to the events actually on the bar — never wider than the fixed
    /// span, never narrower than `minimumRelativeSpan`, and always containing
    /// `now` so the marker has somewhere to be.
    private static func relativeRange(
        now: Date,
        bounds: (first: Date, last: Date)?
    ) -> ClosedRange<Date> {
        let widestLower = now.addingTimeInterval(-relativeLookBehind)
        let widestUpper = now.addingTimeInterval(relativeLookAhead)
        guard let bounds else { return widestLower...widestUpper }

        let margin: TimeInterval = 15 * 60
        // Reach back for a meeting that has already started, but never further
        // than the fixed window — and never LESS than the minimum look-behind,
        // so "now" always has a little history to sit against.
        let lower = min(
            max(bounds.first.addingTimeInterval(-margin), widestLower),
            now.addingTimeInterval(-minimumLookBehind)
        )
        let upper = max(
            min(bounds.last.addingTimeInterval(margin), widestUpper),
            now.addingTimeInterval(minimumLookAhead)
        )
        // A floor so a single short meeting does not collapse the bar around
        // itself and leave a timeline that spans twenty minutes.
        return lower...max(upper, lower.addingTimeInterval(minimumRelativeSpan))
    }

    /// The working day, stretched only as far as the day's own events demand.
    private static func dayRange(
        now: Date,
        bounds: (first: Date, last: Date)?,
        calendar: Calendar
    ) -> ClosedRange<Date> {
        let startOfDay = calendar.startOfDay(for: now)
        let defaultLower = calendar.date(
            byAdding: .hour, value: dayStartHour, to: startOfDay
        ) ?? startOfDay
        let defaultUpper = calendar.date(
            byAdding: .hour, value: dayEndHour, to: startOfDay
        ) ?? startOfDay.addingTimeInterval(24 * 3600)

        // An 07:30 standup or a 21:00 call should not fall off the end of the
        // bar, so the day widens for them rather than clipping them.
        var lower = min(defaultLower, bounds?.first ?? defaultLower)
        var upper = max(defaultUpper, bounds?.last ?? defaultUpper)
        lower = min(lower, now)
        upper = max(upper, now)
        return lower...max(upper, lower.addingTimeInterval(minimumRelativeSpan))
    }
}
