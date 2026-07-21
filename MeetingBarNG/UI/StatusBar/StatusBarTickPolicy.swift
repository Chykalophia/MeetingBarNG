//
//  StatusBarTickPolicy.swift
//  MeetingBarNG
//
//  Decides when the status bar next needs to redraw *because time passed*.
//
//  The app had no clock of its own: every redraw was a side effect of a
//  Defaults change or of the 180-second calendar poll. So "the meeting that is
//  happening now" only became true up to three minutes late, a countdown
//  advanced in three-minute jumps, and the moment a meeting started — the one
//  instant the menu bar most needs to be right — was whenever EventKit
//  happened to be polled next. This policy is the missing clock.
//
//  Pure so the schedule is testable without waiting in real time.
//

import Foundation

enum StatusBarTickPolicy {
    /// Coarse ceiling on staleness. A countdown shown in minutes only needs to
    /// change on the minute, so this exists to bound drift (and to recover from
    /// a missed boundary), not to drive the common case.
    static let maximumInterval: TimeInterval = 60

    /// Instants at which the *rendered* state changes even though nothing about
    /// the calendar did: a meeting starts, a meeting ends, and the point where
    /// "hide the current meeting N minutes after it starts" takes effect.
    ///
    /// Returned unsorted-safe: callers take the earliest strictly-future one.
    static func transitionDates(
        eventStart: Date?,
        eventEnd: Date?,
        ongoingGracePeriod: TimeInterval?
    ) -> [Date] {
        var dates: [Date] = []
        if let eventStart {
            dates.append(eventStart)
            if let ongoingGracePeriod {
                dates.append(eventStart.addingTimeInterval(ongoingGracePeriod))
            }
        }
        if let eventEnd {
            dates.append(eventEnd)
        }
        return dates
    }

    /// The next moment worth redrawing at: the earliest of the upcoming
    /// transitions and the next minute boundary, never further out than
    /// `maximumInterval` and never in the past.
    ///
    /// Aligning to the minute boundary rather than firing every 60s from launch
    /// is what makes a "in 25m" countdown change *when the minute changes*
    /// instead of up to 59 seconds late.
    static func nextFireDate(
        now: Date,
        transitions: [Date],
        calendar: Calendar = .current
    ) -> Date {
        let ceiling = now.addingTimeInterval(maximumInterval)
        let candidates = transitions.filter { $0 > now } + [nextMinuteBoundary(after: now, calendar: calendar)]
        let earliest = candidates.min() ?? ceiling
        return min(earliest, ceiling)
    }

    /// The start of the next wall-clock minute. Falls back to a plain offset if
    /// the calendar cannot resolve the boundary (it always can for `.second`,
    /// but the API is failable).
    static func nextMinuteBoundary(after now: Date, calendar: Calendar = .current) -> Date {
        guard let boundary = calendar.nextDate(
            after: now,
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime
        ) else {
            return now.addingTimeInterval(maximumInterval)
        }
        return boundary
    }

    /// Seconds to wait before the next redraw. Clamped to a small positive
    /// floor: a zero or negative delay would spin the timer, and landing a
    /// hair *before* a transition would redraw with the old state and then wait
    /// a whole minute to correct itself.
    static func delay(now: Date, until fireDate: Date) -> TimeInterval {
        max(0.5, fireDate.timeIntervalSince(now))
    }
}
