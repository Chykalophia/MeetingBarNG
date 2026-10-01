//
//  LocationSuggestions.swift
//  MeetingBarNG
//
//  MapKit-backed location suggestions for the event editor.
//
//  ⚠️ This is the ONLY part of MeetingBarNG that sends anything off the machine.
//  MapKit forwards the typed text to Apple to produce suggestions. That cuts
//  against the local-first principle in ROADMAP.md, so the feature is OFF by
//  default, the Preferences copy says plainly what leaves the Mac, and the gate
//  itself lives in the hostless, unit-tested `LocationAutocompletePolicy` rather
//  than in this file.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Foundation
import MapKit

/// A single suggestion, flattened out of `MKLocalSearchCompletion` so the view
/// never touches MapKit types.
struct LocationSuggestion: Identifiable, Hashable {
    /// Composed from both lines: two different addresses can share a title.
    var id: String { "\(title)|\(subtitle)" }
    let title: String
    let subtitle: String

    /// What goes in the field when picked. The subtitle usually carries the
    /// street and city, which is the part that makes a location useful to
    /// someone reading the invite.
    var fieldValue: String {
        subtitle.isEmpty ? title : "\(title), \(subtitle)"
    }
}

@MainActor
final class LocationSuggestionsModel: NSObject, ObservableObject {
    @Published private(set) var suggestions: [LocationSuggestion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        // Addresses and points of interest; explicitly NOT `.query`, which
        // returns search phrases rather than places.
        completer.resultTypes = [.address, .pointOfInterest]
    }

    /// Updates the suggestion list for `text`, or clears it.
    ///
    /// Every caller goes through the hostless gate, so a disabled feature makes
    /// no request and holds no stale results.
    func update(for text: String, isEnabled: Bool) {
        guard LocationAutocompletePolicy.shouldQuery(text, isEnabled: isEnabled) else {
            // Cancel in flight as well as clearing: a request started before the
            // user deleted back to two characters would otherwise still land.
            completer.cancel()
            if !suggestions.isEmpty { suggestions = [] }
            return
        }
        completer.queryFragment = text
    }

    /// Drops everything, for when the editor closes or a suggestion is taken.
    func clear() {
        completer.cancel()
        if !suggestions.isEmpty { suggestions = [] }
    }
}

extension LocationSuggestionsModel: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results.map {
            LocationSuggestion(title: $0.title, subtitle: $0.subtitle)
        }
        Task { @MainActor [weak self] in
            // Capped: the field sits in a small sheet, and a scrolling wall of
            // twenty addresses is worse than the five most likely.
            self?.suggestions = Array(results.prefix(5))
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Suggestions are a convenience: offline, rate-limited, or refused, the
        // field still works as a plain text field. Failing quietly is correct —
        // an error banner for an optional autocomplete would be noise.
        Task { @MainActor [weak self] in
            self?.suggestions = []
        }
    }
}
