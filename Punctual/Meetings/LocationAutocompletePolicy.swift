//
//  LocationAutocompletePolicy.swift
//  MeetingBarNG
//
//  The one decision that matters for location autocomplete: whether a query
//  leaves this Mac.
//
//  MeetingBarNG is local-first by design — no account, no servers, calendar data
//  stays on the machine (see ROADMAP "Guiding principles"). Location suggestions
//  are the single feature that breaks that, because MapKit sends the typed text
//  to Apple. So the feature is OFF by default and the gate is hostless and
//  unit-tested rather than an `if` buried in a view: "nothing is sent unless the
//  user turned this on" should be provable, not inspected by hand.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Foundation

public enum LocationAutocompletePolicy {
    /// Below this, a query is noise: one or two characters match half the world,
    /// and every keystroke is a separate network request.
    public static let minimumQueryLength = 3

    /// Whether `text` may be sent to the suggestion service.
    ///
    /// Both conditions are required and the enabled check is FIRST, so a disabled
    /// feature short-circuits before the query is even examined.
    public static func shouldQuery(
        _ text: String,
        isEnabled: Bool,
        minimumLength: Int = minimumQueryLength
    ) -> Bool {
        guard isEnabled else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= minimumLength
    }

    /// Whether suggestions should be shown for the current field contents.
    ///
    /// Separate from `shouldQuery` because a stale result set must disappear the
    /// moment the field drops below the threshold — otherwise deleting back to
    /// two characters leaves the previous suggestions on screen, looking like
    /// live results for a query that was never sent.
    public static func shouldPresentResults(
        for text: String,
        isEnabled: Bool,
        resultCount: Int,
        minimumLength: Int = minimumQueryLength
    ) -> Bool {
        guard resultCount > 0 else { return false }
        return shouldQuery(text, isEnabled: isEnabled, minimumLength: minimumLength)
    }
}
