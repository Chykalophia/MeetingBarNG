//
//  CalendarSourceSelection.swift
//  MeetingBarNG
//
//  Which calendar SOURCES are connected, as pure hostless logic.
//
//  MeetingBar historically had exactly one active provider: picking Google
//  Calendar meant giving up macOS Calendar, so anyone with an Exchange or
//  iCloud calendar alongside a Google one had to choose which half of their day
//  the app could see. This type replaces that either/or with a set, so macOS
//  Calendar and the direct Google provider can be connected at the same time.
//
//  It deliberately knows nothing about `EventStoreProvider`, `Defaults` or
//  EventKit — `CalendarSourceKind` mirrors the app-layer enum the same way
//  `DiagnosticsProvider` already does, and `CalendarSourceSelection+MeetingBar`
//  bridges the two. That keeps every rule here (the migration, the
//  last-source-standing invariant, availability filtering, dedup precedence)
//  testable with no host at all.
//

import Foundation

/// Hostless mirror of the app layer's `EventStoreProvider`. Kept separate so
/// this file has no AppKit/Defaults dependency; see `DiagnosticsProvider` for
/// the same pattern.
public enum CalendarSourceKind: String, Codable, Hashable, Sendable, CaseIterable {
    case macOSEventKit = "MacOS Calendar App"
    case googleCalendar = "Google Calendar API"

    /// Display order wherever sources are listed. macOS Calendar leads because
    /// it needs no setup and is right for anyone without a specific reason.
    public static let displayOrder: [CalendarSourceKind] = [.macOSEventKit, .googleCalendar]

    /// Which copy of a duplicated meeting survives — LOWER WINS. Google leads
    /// here and only here: when the same invite arrives from both sources, the
    /// direct Google copy carries real attendee response status and Google's own
    /// conferencing data, where EventKit's mirrored copy routinely flattens
    /// attendee status and leaves the conference link recoverable only by
    /// scraping the notes. Display order and precedence are answering different
    /// questions, so they are allowed to disagree.
    public var deduplicationPriority: Int {
        switch self {
        case .googleCalendar: return 0
        case .macOSEventKit: return 1
        }
    }

    /// Localization key naming this source on screen. Lives here so the source
    /// picker, the calendar list's account headers and anywhere else naming a
    /// source cannot drift apart.
    public var titleKey: String {
        switch self {
        case .macOSEventKit: return "onboarding_apple_calendar_title"
        case .googleCalendar: return "onboarding_google_calendar_title"
        }
    }

    /// Only EventKit can create, edit or delete events and reminders; the Google
    /// provider is read-only in this app. Anything offering a write action has to
    /// gate on an ENABLED EventKit rather than on "the active provider", which is
    /// the concept multi-source removes.
    public var supportsWrites: Bool {
        switch self {
        case .macOSEventKit: return true
        case .googleCalendar: return false
        }
    }
}

/// The set of connected calendar sources, plus the rules that keep it coherent.
///
/// Always non-empty: every operation that would empty it is refused instead.
/// A zero-source install fetches nothing and renders an empty dropdown that
/// looks broken rather than configured, and there is already a per-calendar
/// tick-box for "show me nothing from here".
public struct CalendarSourceSelection: Equatable, Sendable {
    /// Never empty, and always in `CalendarSourceKind.displayOrder`.
    public private(set) var enabled: [CalendarSourceKind]

    public init(enabled: [CalendarSourceKind]) {
        let normalized = Self.normalize(enabled)
        self.enabled = normalized.isEmpty ? [.macOSEventKit] : normalized
    }

    public func isEnabled(_ kind: CalendarSourceKind) -> Bool {
        enabled.contains(kind)
    }

    /// The source that handles writes, or nil when none is connected. Event
    /// creation/editing and reminders hang off this.
    public var writeSource: CalendarSourceKind? {
        enabled.first(where: \.supportsWrites)
    }

    /// Enabling an already-enabled source is a no-op, so callers can drive this
    /// straight from a toggle without checking first.
    public func enabling(_ kind: CalendarSourceKind) -> CalendarSourceSelection {
        guard !isEnabled(kind) else { return self }
        return CalendarSourceSelection(enabled: enabled + [kind])
    }

    /// Disabling the LAST enabled source is refused and returns `self`
    /// unchanged — see the type's note on why zero sources is not a state worth
    /// modelling. Callers should use `canDisable(_:)` to grey out the control
    /// rather than letting the click silently do nothing.
    public func disabling(_ kind: CalendarSourceKind) -> CalendarSourceSelection {
        guard canDisable(kind) else { return self }
        return CalendarSourceSelection(enabled: enabled.filter { $0 != kind })
    }

    public func canDisable(_ kind: CalendarSourceKind) -> Bool {
        isEnabled(kind) && enabled.count > 1
    }

    public func setting(_ kind: CalendarSourceKind, enabled shouldEnable: Bool) -> CalendarSourceSelection {
        shouldEnable ? enabling(kind) : disabling(kind)
    }

    /// Drops sources this build cannot actually use — Google without OAuth
    /// credentials compiled in, principally. Applied on read rather than on
    /// write so that a user who supplies credentials later gets their previous
    /// selection back instead of a silently erased one.
    ///
    /// If filtering would empty the set, macOS Calendar is restored: it is
    /// always available, and an install that can reach no source at all is worse
    /// than one quietly returned to the default.
    public func availableOnly(_ isAvailable: (CalendarSourceKind) -> Bool) -> CalendarSourceSelection {
        let surviving = enabled.filter(isAvailable)
        return CalendarSourceSelection(enabled: surviving.isEmpty ? [.macOSEventKit] : surviving)
    }

    /// One-time migration off the single `eventStoreProvider` key. The provider
    /// an existing install was using becomes its one enabled source, so updating
    /// changes nothing until the user opts into a second one.
    public static func migrating(fromSingleProvider provider: CalendarSourceKind) -> CalendarSourceSelection {
        CalendarSourceSelection(enabled: [provider])
    }

    /// Deduplicated and sorted into display order, so persisted values can never
    /// drift into a different order than the UI renders.
    private static func normalize(_ kinds: [CalendarSourceKind]) -> [CalendarSourceKind] {
        CalendarSourceKind.displayOrder.filter(kinds.contains)
    }
}
