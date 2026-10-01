//
//  EventDeduplication.swift
//  MeetingBarNG
//
//  Pure, hostless cross-calendar duplicate detection. The same underlying event
//  can arrive on two selected calendars (e.g. a shared invite that lives on both
//  a personal and a work calendar), as two EventKit copies, or — once more than
//  one calendar SOURCE is connected — as one copy from macOS Calendar and
//  another from the direct Google provider. Those show up as visible duplicates
//  in the dropdown. This collapses them, keyed on the provider's shared external
//  identifier when present and otherwise on a normalized title + starting minute
//  composite. Deterministic so it can be unit-tested without any
//  AppKit/EventKit/Defaults host.
//
//  The composite path carries the real weight: only EventKit populates
//  `externalIdentifier`, so every Google-Calendar-sourced event falls through to
//  it. That path is therefore tolerant on purpose — insensitive to case,
//  diacritics, whitespace, sub-minute drift and differing end times — because a
//  key stricter than the user's own eyes produces duplicate rows that look
//  identical and read as a bug.
//
//  WHICH COPY SURVIVES is `sourcePriority`, added when multi-source landed.
//  With one source it is 0 everywhere and the first occurrence wins, exactly as
//  before. With Apple and Google both connected the Google copy is preferred:
//  it carries real attendee response status and Google's own conferencing data,
//  where EventKit's mirrored copy routinely arrives with attendee status flattened
//  and the conference link only recoverable by scraping the notes.
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
    /// Tie-break for which copy of a collapsed meeting survives — LOWER WINS.
    /// Defaults to 0 so a single-source install (and every existing call site)
    /// keeps the historical "first occurrence wins" behaviour untouched.
    var sourcePriority: Int = 0
}

enum EventDeduplication {
    /// Returns the `sourceIndex` of each event to keep, dropping duplicates.
    /// Output stays in the input's relative order.
    ///
    /// Duplicates are grouped TRANSITIVELY: if A and B share a composite key and
    /// B and C share an external identifier, all three are one meeting. The
    /// previous single-pass walk could not see that — it dropped B for matching
    /// A, which meant B's identifier was never recorded, and C then survived as a
    /// third row of the same meeting. Grouping first and choosing second is also
    /// what makes `sourcePriority` possible at all: a preferred copy has to be
    /// able to win over one that was merely earlier in the array.
    static func keptIndices(_ events: [DeduplicationEvent]) -> [Int] {
        guard !events.isEmpty else { return [] }

        var groups = DisjointSet(count: events.count)

        // Either signal is sufficient to merge two events. The identifier
        // catches copies whose title or time drifted apart; the composite
        // catches copies whose identifiers drifted apart. Requiring both — or
        // checking the identifier FIRST and short-circuiting — is what left a
        // duplicate on screen: two rows reading "12:00 PM · Peter: Lunch"
        // survived purely because the providers disagreed about an id the user
        // cannot see.
        var firstAtComposite: [String: Int] = [:]
        var firstAtIdentifier: [String: Int] = [:]

        for (position, event) in events.enumerated() {
            let composite = compositeKey(for: event)
            if let existing = firstAtComposite[composite] {
                groups.union(existing, position)
            } else {
                firstAtComposite[composite] = position
            }

            if let identifier = sharedIdentifier(for: event) {
                if let existing = firstAtIdentifier[identifier] {
                    groups.union(existing, position)
                } else {
                    firstAtIdentifier[identifier] = position
                }
            }
        }

        // One survivor per group: best `sourcePriority`, ties broken by the
        // earlier position so same-source behaviour stays first-wins.
        var survivorByGroup: [Int: Int] = [:]
        for position in events.indices {
            let group = groups.root(of: position)
            guard let incumbent = survivorByGroup[group] else {
                survivorByGroup[group] = position
                continue
            }
            if events[position].sourcePriority < events[incumbent].sourcePriority {
                survivorByGroup[group] = position
            }
        }

        let survivors = Set(survivorByGroup.values)
        return events.indices
            .filter { survivors.contains($0) }
            .map { events[$0].sourceIndex }
    }

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

/// Minimal union-find over array positions, with path halving and union by size.
/// Local to deduplication — it exists only so duplicate groups can be resolved
/// transitively before a survivor is chosen.
private struct DisjointSet {
    private var parent: [Int]
    private var size: [Int]

    init(count: Int) {
        parent = Array(0..<count)
        size = Array(repeating: 1, count: count)
    }

    mutating func root(of element: Int) -> Int {
        var current = element
        while parent[current] != current {
            parent[current] = parent[parent[current]]
            current = parent[current]
        }
        return current
    }

    mutating func union(_ lhs: Int, _ rhs: Int) {
        let lhsRoot = root(of: lhs)
        let rhsRoot = root(of: rhs)
        guard lhsRoot != rhsRoot else { return }
        let (larger, smaller) = size[lhsRoot] >= size[rhsRoot]
            ? (lhsRoot, rhsRoot)
            : (rhsRoot, lhsRoot)
        parent[smaller] = larger
        size[larger] += size[smaller]
    }
}
