//
//  DaySummaryGreeting.swift
//  MeetingBarNG
//
//  Hostless policy for the menu's day-summary greeting header (Dot parity).
//  Pure value types + math only — no AppKit/Defaults/EventKit. The host layer
//  (StatusBarMenuState) resolves the user's name and MenuBuilder does the
//  localized string interpolation, mirroring how StatusBarTitlePolicy keeps
//  `.loco()` out of the logic module.
//

import Foundation

/// Coarse time-of-day bucket driving the greeting ("Good morning/afternoon/evening").
enum GreetingTimeOfDay: Equatable {
    case morning
    case afternoon
    case evening
}

/// A single event projected to just what the day summary needs. `MBEvent` is
/// host-layer, so the pure policy takes this flat shadow (same convention as
/// EventSelectionEvent / StatusBarEventPresentationInput).
struct DaySummaryInterval: Equatable {
    let start: Date
    let end: Date
    let isAllDay: Bool
}

/// Input to `DaySummaryPolicy.summary`. `events` are the day's events (the
/// caller supplies today's list); all-day entries are ignored by the policy.
struct DaySummaryInput: Equatable {
    let now: Date
    let events: [DaySummaryInterval]
}

/// Structured result the header renders. Kept free of any formatted/localized
/// strings so it stays deterministic and unit-testable.
struct DaySummary: Equatable {
    let timeOfDay: GreetingTimeOfDay
    /// Count of the day's timed (non-all-day) events.
    let eventCount: Int
    /// Unbooked minutes between `now` and the end of the calendar day.
    let freeMinutes: Int
}

enum DaySummaryPolicy {
    static func summary(input: DaySummaryInput, calendar: Calendar) -> DaySummary {
        let timedEvents = input.events.filter { !$0.isAllDay }
        return DaySummary(
            timeOfDay: timeOfDay(now: input.now, calendar: calendar),
            eventCount: timedEvents.count,
            freeMinutes: freeMinutes(now: input.now, events: timedEvents, calendar: calendar)
        )
    }

    static func timeOfDay(now: Date, calendar: Calendar) -> GreetingTimeOfDay {
        let hour = calendar.component(.hour, from: now)
        if hour < 12 { return .morning }
        if hour < 17 { return .afternoon }
        return .evening
    }

    /// Free (unbooked) minutes between `now` and the end of the calendar day.
    ///
    /// All-day events are excluded (they'd swallow the whole window); each timed
    /// event is clamped to `[now, endOfDay]` so meetings that started earlier or
    /// run past midnight are counted correctly; overlapping/adjacent meetings are
    /// merged so shared minutes aren't double-counted.
    static func freeMinutes(now: Date, events: [DaySummaryInterval], calendar: Calendar) -> Int {
        let startOfDay = calendar.startOfDay(for: now)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay), now < endOfDay else {
            return 0
        }
        let windowSeconds = endOfDay.timeIntervalSince(now)
        guard windowSeconds > 0 else { return 0 }

        let coveredSeconds = mergedCoveredSeconds(
            events: events, windowStart: now, windowEnd: endOfDay
        )
        let freeSeconds = max(0, windowSeconds - coveredSeconds)
        return Int((freeSeconds / 60).rounded(.down))
    }

    /// Total seconds inside `[windowStart, windowEnd]` covered by the given timed
    /// events, with overlaps merged. The reusable primitive: total meeting time
    /// is `mergedCoveredSeconds`, free time is `window - mergedCoveredSeconds`.
    private static func mergedCoveredSeconds(
        events: [DaySummaryInterval],
        windowStart: Date,
        windowEnd: Date
    ) -> TimeInterval {
        let clamped = events
            .filter { !$0.isAllDay }
            .compactMap { event -> (start: Date, end: Date)? in
                let start = max(event.start, windowStart)
                let end = min(event.end, windowEnd)
                return end > start ? (start, end) : nil
            }
            .sorted { $0.start < $1.start }

        var covered: TimeInterval = 0
        var currentStart: Date?
        var currentEnd: Date?
        for interval in clamped {
            guard let cStart = currentStart, let cEnd = currentEnd else {
                currentStart = interval.start
                currentEnd = interval.end
                continue
            }
            if interval.start <= cEnd {
                currentEnd = max(cEnd, interval.end)
            } else {
                covered += cEnd.timeIntervalSince(cStart)
                currentStart = interval.start
                currentEnd = interval.end
            }
        }
        if let cStart = currentStart, let cEnd = currentEnd {
            covered += cEnd.timeIntervalSince(cStart)
        }
        return covered
    }
}
