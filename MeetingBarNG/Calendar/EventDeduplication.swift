//
//  EventDeduplication.swift
//  MeetingBarNG
//
//  Pure, hostless cross-calendar duplicate detection. The same underlying event
//  can arrive on two selected calendars (e.g. a shared invite that lives on both
//  a personal and a work calendar) or as two EventKit copies; those show up as
//  visible duplicates in the dropdown. This collapses them, keeping the first
//  occurrence, keyed on the provider's shared external identifier when present
//  and otherwise on a normalized title + starting minute composite. Deterministic
//  so it can be unit-tested without any AppKit/EventKit/Defaults host.
//
//  The composite path carries the real weight: only EventKit populates
//  `externalIdentifier`, so every Google-Calendar-sourced event falls through to
//  it. That path is therefore tolerant on purpose — insensitive to case,
//  diacritics, whitespace, sub-minute drift and differing end times — because a
//  key stricter than the user's own eyes produces duplicate rows that look
//  identical and read as a bug.
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
    /// Carried but deliberately NOT part of the identity key. Two copies of one
    /// meeting frequently disagree about its end — a 30-minute block on one
    /// calendar and 60 on another, or a duration that drifted when an invite was
    /// forwarded — while agreeing on title and start. Keying on the end made
    /// those survive as two rows that, with end times hidden (the default), were
    /// literally indistinguishable on screen. Same normalized title + same
    /// starting minute + same all-day-ness is treated as the same meeting.
    ///
    /// The trade: two genuinely different meetings sharing a title and start
    /// minute now collapse to one row. They were already indistinguishable in a
    /// list that shows title and start, so showing one is the better failure.
    let endDate: Date
    let isAllDay: Bool
}

enum EventDeduplication {
    /// Walks `events` in order and returns the `sourceIndex` of each event to
    /// keep, dropping later duplicates. Order is preserved and the first
    /// occurrence always wins.
    static func keptIndices(_ events: [DeduplicationEvent]) -> [Int] {
        var seenIdentifiers = Set<String>()
        var seenComposites = Set<String>()
        var kept: [Int] = []
        kept.reserveCapacity(events.count)

        for event in events {
            let composite = compositeKey(for: event)
            let identifier = sharedIdentifier(for: event)

            // EITHER signal is sufficient. The identifier catches copies whose
            // title or time drifted apart; the composite catches copies whose
            // identifiers drifted apart. Requiring both, or checking the
            // identifier FIRST and returning, is what left a duplicate on screen:
            // two rows reading "12:00 PM · Peter: Lunch" survived purely because
            // the providers disagreed about an id the user cannot see.
            let alreadySeen =
                seenComposites.contains(composite)
                || (identifier.map(seenIdentifiers.contains) ?? false)
            guard !alreadySeen else { continue }

            seenComposites.insert(composite)
            if let identifier { seenIdentifiers.insert(identifier) }
            kept.append(event.sourceIndex)
        }
        return kept
    }

    /// The shared external identifier is the strongest signal: copies of the
    /// same event across calendars/accounts carry the same one. When it's
    /// missing (nil or empty — e.g. a Google-backed event or a local event
    /// without one) fall back to a composite of the normalized title and the
    /// STARTING MINUTE, which catches true duplicates that differ only by the
    /// calendar they came from — or by an end time the user cannot see.
    /// Prefixes keep the two key spaces from colliding.
    /// The provider's shared identifier, when it has one. Copies of a single
    /// invite across calendars usually carry the same one — but only usually,
    /// which is why it is one of two signals rather than the deciding one.
    private static func sharedIdentifier(for event: DeduplicationEvent) -> String? {
        guard let identifier = event.externalIdentifier, !identifier.isEmpty else { return nil }
        return identifier
    }

    /// Title + starting minute + all-day-ness: what the user can actually see on
    /// the row. Two events matching here are indistinguishable on screen, so
    /// showing both reads as a bug regardless of what the providers think.
    private static func compositeKey(for event: DeduplicationEvent) -> String {
        "composite:\(normalizedTitle(event.title))|\(startMinute(event))|\(event.isAllDay)"
    }

    /// Case-, diacritic- AND whitespace-insensitive.
    ///
    /// Diacritic folding is locale-independent and `.lowercased()` uses Unicode's
    /// default case mapping, so the result never depends on the current locale.
    /// Whitespace is normalized because copies of one meeting routinely pick up a
    /// trailing space or a non-breaking space in transit between providers —
    /// invisible on screen, but previously enough to defeat the key and leave the
    /// user staring at two rows that looked character-for-character identical.
    private static func normalizedTitle(_ title: String) -> String {
        title
            .folding(options: .diacriticInsensitive, locale: nil)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Whole minutes since the reference date, truncated — deliberately the same
    /// resolution the UI displays.
    ///
    /// Exact `TimeInterval` equality meant two copies a few seconds apart keyed
    /// differently while both rendered "12:00 PM", which is indistinguishable to
    /// the user and so reads as a plain bug. Truncating (rather than rounding)
    /// matches the displayed minute exactly: anything from 12:00:00 to 12:00:59
    /// shows as 12:00 PM and now keys as 12:00 PM too.
    private static func startMinute(_ event: DeduplicationEvent) -> Int {
        Int((event.startDate.timeIntervalSinceReferenceDate / 60).rounded(.down))
    }
}
