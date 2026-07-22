//
//  EventDeduplication.swift
//  MeetingBarNG
//
//  Pure, hostless cross-calendar duplicate detection. The same underlying event
//  can arrive on two selected calendars (e.g. a shared invite that lives on both
//  a personal and a work calendar) or as two EventKit copies; those show up as
//  visible duplicates in the dropdown. This collapses them, keeping the first
//  occurrence, keyed on the provider's shared external identifier when present
//  and otherwise on a normalized title + time-window composite. Deterministic so
//  it can be unit-tested without any AppKit/EventKit/Defaults host.
//

import Foundation

/// A minimal projection of an event used only for duplicate detection. Carries
/// its `sourceIndex` back into the caller's array so the caller can keep the
/// surviving events without this type needing to know about `MBEvent`.
struct DeduplicationEvent {
    let sourceIndex: Int
    let externalIdentifier: String?
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
}

enum EventDeduplication {
    /// Walks `events` in order and returns the `sourceIndex` of each event to
    /// keep, dropping later duplicates. Order is preserved and the first
    /// occurrence always wins.
    static func keptIndices(_ events: [DeduplicationEvent]) -> [Int] {
        var seenKeys = Set<String>()
        var kept: [Int] = []
        kept.reserveCapacity(events.count)
        for event in events where seenKeys.insert(deduplicationKey(for: event)).inserted {
            kept.append(event.sourceIndex)
        }
        return kept
    }

    /// The shared external identifier is the strongest signal: copies of the
    /// same event across calendars/accounts carry the same one. When it's
    /// missing (nil or empty — e.g. a Google-backed event or a local event
    /// without one) fall back to a composite of the normalized title and the
    /// exact time window, which catches true duplicates that differ only by the
    /// calendar they came from. Prefixes keep the two key spaces from colliding.
    private static func deduplicationKey(for event: DeduplicationEvent) -> String {
        if let externalIdentifier = event.externalIdentifier, !externalIdentifier.isEmpty {
            return "ext:\(externalIdentifier)"
        }
        // Diacritic folding is locale-independent; `.lowercased()` uses Unicode's
        // default case mapping — together they give a deterministic, case- and
        // diacritic-insensitive title without depending on the current locale.
        let normalizedTitle = event.title
            .folding(options: .diacriticInsensitive, locale: nil)
            .lowercased()
        let start = event.startDate.timeIntervalSinceReferenceDate
        let end = event.endDate.timeIntervalSinceReferenceDate
        return "composite:\(normalizedTitle)|\(start)|\(end)|\(event.isAllDay)"
    }
}
