//
//  WorldClockPanel.swift
//  MeetingBarNG
//
//  Pure, hostless core for the multi-zone world-clock panel (Dot parity). The
//  panel is a small window listing several user-chosen time zones with their
//  current local time and a "Tomorrow"/"Yesterday" tag when a zone's calendar
//  day differs from the reference zone's. This complements the world-clock
//  *token* (one zone in the menu bar, `MenuBarCompositionPolicy.worldClockText`)
//  — the panel is many zones at once.
//
//  Mirrors `MenuBarCompositionPolicy.clockText` / `worldClockText` so the panel
//  and the token format times identically. Kept free of AppKit/Defaults/I18N so
//  it stays fully unit-testable; the SwiftUI view + window host live in the app
//  target.
//

import Foundation

/// A single user-chosen zone in the panel: a time-zone identifier plus a display
/// label (derived from the identifier via `WorldClockPanelPolicy.cityLabel`
/// unless the caller supplies a custom one).
struct WorldClockZone: Equatable {
    let identifier: String
    let label: String
}

/// A rendered panel row: the label, the formatted local time in that zone, and
/// the whole-day offset of that zone's calendar day vs the reference zone's day
/// (-1 yesterday / 0 today / +1 tomorrow) so the view can show a Tomorrow /
/// Yesterday tag.
struct WorldClockEntry: Equatable {
    let label: String
    let time: String
    let dayOffset: Int
}

/// Pure formatters for the world-clock panel. Hostless and fully unit-tested.
enum WorldClockPanelPolicy {
    /// One `WorldClockEntry` per zone, preserving order. Each entry's `time` is
    /// `now` formatted in that zone (12h/24h per `use24Hour`); `dayOffset` is the
    /// whole-day difference between that zone's calendar day and the reference
    /// zone's calendar day at `now`. An unresolvable identifier falls back to the
    /// reference zone (offset 0). An empty `zones` yields `[]`.
    static func entries(
        zones: [WorldClockZone],
        now: Date,
        use24Hour: Bool,
        referenceZone: TimeZone,
        locale: Locale
    ) -> [WorldClockEntry] {
        zones.map { zone in
            let timeZone = TimeZone(identifier: zone.identifier) ?? referenceZone
            return WorldClockEntry(
                label: zone.label,
                time: timeText(now: now, timeZone: timeZone, use24Hour: use24Hour, locale: locale),
                dayOffset: dayOffset(
                    now: now, zone: timeZone, referenceZone: referenceZone, locale: locale
                )
            )
        }
    }

    /// The current time in `timeZone`, formatted like
    /// `MenuBarCompositionPolicy.clockText` (localized 12h/24h template), pinned
    /// to the chosen zone.
    static func timeText(now: Date, timeZone: TimeZone, use24Hour: Bool, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(use24Hour ? "Hmm" : "hmma")
        return formatter.string(from: now)
    }

    /// Whole-day difference of `zone`'s calendar day vs `referenceZone`'s day at
    /// `now`: -1 (yesterday), 0 (today), +1 (tomorrow), and beyond near the date
    /// line. Computed by reading each zone's civil (year/month/day) at `now`,
    /// re-anchoring both to UTC midnight, and counting whole days between them —
    /// so it stays correct regardless of the zones' UTC offsets and DST.
    static func dayOffset(now: Date, zone: TimeZone, referenceZone: TimeZone, locale: Locale) -> Int {
        let referenceDay = civilDay(now: now, zone: referenceZone, locale: locale)
        let zoneDay = civilDay(now: now, zone: zone, locale: locale)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? referenceZone
        utcCalendar.locale = locale
        return utcCalendar.dateComponents([.day], from: referenceDay, to: zoneDay).day ?? 0
    }

    /// The civil (year/month/day) of `now` as seen in `zone`, re-anchored to UTC
    /// midnight so day differences between zones become plain whole-day spans.
    private static func civilDay(now: Date, zone: TimeZone, locale: Locale) -> Date {
        var zoneCalendar = Calendar(identifier: .gregorian)
        zoneCalendar.timeZone = zone
        zoneCalendar.locale = locale
        let components = zoneCalendar.dateComponents([.year, .month, .day], from: now)

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? zone
        utcCalendar.locale = locale
        return utcCalendar.date(
            from: DateComponents(year: components.year, month: components.month, day: components.day)
        ) ?? now
    }

    /// A readable default label derived from a time-zone identifier: the last
    /// "/"-separated component with underscores replaced by spaces, e.g.
    /// "America/Los_Angeles" → "Los Angeles", "Europe/Isle_of_Man" → "Isle of
    /// Man", "UTC" → "UTC".
    static func cityLabel(fromIdentifier identifier: String) -> String {
        let lastComponent = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return lastComponent.replacingOccurrences(of: "_", with: " ")
    }
}
