//
//  EventReminderOverrides.swift
//  MeetingBarNG
//
//  Storage for per-event start-reminder overrides: "remind me 30 minutes before
//  THIS one", or "don't remind me about this one at all".
//
//  The decision logic is hostless in `NotificationPlanner.startAction`; this file
//  is only the app-target storage, which needs `Defaults.Serializable`.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Defaults
import Foundation

/// One stored override.
///
/// Keyed on `MBEvent.id`, which is PER-OCCURRENCE — EventKit's series-shared
/// identifier is kept separately as `scriptIdentifier`. So overriding one
/// instance of a recurring standup affects only that instance, which is the
/// behaviour someone silencing "this Thursday's" would expect.
struct EventReminderOverride: Codable, Defaults.Serializable, Hashable {
    let id: String
    /// When the event ends, so a finished event's override can be pruned. Same
    /// mechanism `ProcessedEvent` uses for dismissals — without it the list
    /// grows forever, one entry per meeting ever adjusted.
    let eventEndDate: Date
    /// Seconds before the start. `nil` means no reminder for this event at all.
    let offsetSeconds: Int?

    var planningOverride: StartReminderOverride {
        guard let offsetSeconds else { return .suppressed }
        return .offset(TimeInterval(offsetSeconds))
    }
}

enum EventReminderOverrideStore {
    /// The override for one event, or `nil` to follow the global setting.
    static func override(for id: String, in overrides: [EventReminderOverride]) -> StartReminderOverride? {
        overrides.first { $0.id == id }?.planningOverride
    }

    /// Drops overrides whose event has already ended, mirroring
    /// `EventActionPolicy.cleanupExpired`.
    static func cleanupExpired(
        _ overrides: [EventReminderOverride],
        now: Date
    ) -> [EventReminderOverride] {
        overrides.filter { $0.eventEndDate.timeIntervalSince(now) > 0 }
    }

    // MARK: - Writes

    /// Sets or replaces the override for an event.
    ///
    /// Replaces rather than appends: two entries for one id would make the
    /// winner depend on array order, and `first(where:)` would silently pick the
    /// stale one.
    @MainActor
    static func set(_ override: StartReminderOverride, for event: MBEvent) {
        let offsetSeconds: Int?
        switch override {
        case .suppressed: offsetSeconds = nil
        case .offset(let seconds): offsetSeconds = Int(seconds)
        }
        var stored = Defaults[.eventReminderOverrides].filter { $0.id != event.id }
        stored.append(EventReminderOverride(
            id: event.id,
            eventEndDate: event.endDate,
            offsetSeconds: offsetSeconds
        ))
        Defaults[.eventReminderOverrides] = stored
    }

    /// Returns the event to the global setting.
    @MainActor
    static func clear(for event: MBEvent) {
        Defaults[.eventReminderOverrides].removeAll { $0.id == event.id }
    }

    /// Prunes finished events' overrides. Called on the same cadence as the
    /// other housekeeping rather than on a timer of its own.
    @MainActor
    static func pruneExpired(now: Date = Date()) {
        let current = Defaults[.eventReminderOverrides]
        let pruned = cleanupExpired(current, now: now)
        // Only write when something actually changed: an unconditional write
        // wakes every Defaults observer, including the menu-bar redraw.
        if pruned.count != current.count {
            Defaults[.eventReminderOverrides] = pruned
        }
    }
}
