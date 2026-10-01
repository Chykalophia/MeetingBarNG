//
//  EventSearch.swift
//  MeetingBarNG
//
//  Hostless full-text ranked event search (Dot parity). Pure and deterministic:
//  it operates on `SearchableEvent` value projections (not MBEvent), so it lives
//  in the MeetingBarLogic module and is unit-tested without a host. Mirrors the
//  EventFiltering "value type + pure function + bridge" pattern. This is the data
//  layer FOR the Command Bar; it builds no UI. No AI/LLM — text matching only.
//

import Foundation

/// Flat, EventKit-free projection of an event for ranked search. `sourceIndex`
/// maps a result back to the caller's original `[MBEvent]` (same convention as
/// EventFilterEvent / EventSelectionEvent).
struct SearchableEvent: Equatable {
    let sourceIndex: Int
    let id: String
    let title: String
    let notes: String?
    let location: String?
    /// Pre-flattened attendee + organizer names and emails ("people"), so the
    /// pure layer never sees MBEventAttendee / MBEventOrganizer.
    let attendees: [String]
}

/// Per-field weights for scoring. Higher weight ⇒ a match in that field ranks
/// the event higher. Mirrors the *Settings structs; `.default` is the built-in.
struct SearchFieldWeights: Equatable {
    let title: Double
    let attendees: Double
    let location: Double
    let notes: Double

    /// Title wins (you search a standup by name); people next (the meeting with
    /// Dana); location (room/"zoom"); notes lowest (long, noisy free text).
    static let `default` = SearchFieldWeights(title: 1.0, attendees: 0.7, location: 0.6, notes: 0.4)
}

/// A ranked search hit. `sourceIndex` indexes back into the caller's array.
struct EventSearchResult: Equatable {
    let sourceIndex: Int
    let id: String
    let score: Double
}

/// Case- and diacritic-insensitive text folding applied to both event fields and
/// query terms before matching. `locale: nil` keeps results deterministic and
/// dodges locale-specific casing surprises (e.g. the Turkish dotless-i).
enum TextNormalization {
    static func fold(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil
        )
    }
}

enum EventSearch {
    /// Ranks `events` best-first for `query`.
    ///
    /// - An empty/whitespace query returns ALL events in input order (score 0),
    ///   so the caller can show recents/defaults.
    /// - Multi-term queries use AND semantics: an event must match every term (in
    ///   some field) to appear — so "team sync" finds "Weekly Team Sync".
    /// - Score is the sum of each term's best-field score; ties break by
    ///   `sourceIndex` ascending (stable, preserving the caller's input order).
    static func rank(
        _ events: [SearchableEvent],
        query: String,
        weights: SearchFieldWeights = .default
    ) -> [EventSearchResult] {
        let terms = TextNormalization.fold(query)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        guard !terms.isEmpty else {
            return events.map { EventSearchResult(sourceIndex: $0.sourceIndex, id: $0.id, score: 0) }
        }

        var results: [EventSearchResult] = []
        for event in events {
            let fields = FoldedFields(event: event)
            var total = 0.0
            var matchedAll = true
            for term in terms {
                let best = bestFieldScore(term: term, fields: fields, weights: weights)
                guard best > 0 else {
                    matchedAll = false
                    break
                }
                total += best
            }
            if matchedAll {
                results.append(EventSearchResult(sourceIndex: event.sourceIndex, id: event.id, score: total))
            }
        }

        return results.sorted {
            $0.score != $1.score ? $0.score > $1.score : $0.sourceIndex < $1.sourceIndex
        }
    }

    // MARK: - Internal

    /// Every field folded once per rank() call (not once per term).
    private struct FoldedFields {
        let title: String
        let location: String?
        let notes: String?
        let attendees: [String]

        init(event: SearchableEvent) {
            title = TextNormalization.fold(event.title)
            location = event.location.map(TextNormalization.fold)
            notes = event.notes.map(TextNormalization.fold)
            attendees = event.attendees.map(TextNormalization.fold)
        }
    }

    private static func bestFieldScore(
        term: String,
        fields: FoldedFields,
        weights: SearchFieldWeights
    ) -> Double {
        var best = weights.title * matchTier(term: term, in: fields.title)
        if let location = fields.location {
            best = max(best, weights.location * matchTier(term: term, in: location))
        }
        if let notes = fields.notes {
            best = max(best, weights.notes * matchTier(term: term, in: notes))
        }
        for attendee in fields.attendees {
            best = max(best, weights.attendees * matchTier(term: term, in: attendee))
        }
        return best
    }

    /// Match strength of `term` within an already-folded `field`:
    /// whole-field exact = 4, field prefix = 3, word-boundary prefix = 2,
    /// substring = 1, none = 0.
    private static func matchTier(term: String, in field: String) -> Double {
        guard !field.isEmpty, !term.isEmpty else { return 0 }
        if field == term { return 4 }
        if field.hasPrefix(term) { return 3 }
        if hasWordBoundaryPrefix(term: term, in: field) { return 2 }
        if field.contains(term) { return 1 }
        return 0
    }

    private static func hasWordBoundaryPrefix(term: String, in field: String) -> Bool {
        let separators: Set<Character> = [" ", "-", "_", ".", ",", "/", ":"]
        for token in field.split(whereSeparator: { separators.contains($0) }) where token.hasPrefix(term) {
            return true
        }
        return false
    }
}
