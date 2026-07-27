//
//  PreferencesNavigation.swift
//  MeetingBarNG
//
//  One channel for "take me to that other pane".
//
//  Settings that live on one pane sometimes depend on a setting that lives on
//  another — auto-join opens meetings in whatever Joining decided, and saying so
//  without offering the way there is the dead-end advice the Preferences UX
//  overhaul exists to remove. A pane cannot reach `PreferencesShellV2`'s
//  selection state directly, so it asks here and the window obeys.
//
//  Deliberately tiny and one-shot: the request is cleared as soon as it is
//  honoured, so it can never fight the user's own sidebar clicks.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026
//  (Preferences UX overhaul, Phase 2 — the IA restructure).
//

import Observation

@MainActor
@Observable
final class PreferencesNavigation {
    static let shared = PreferencesNavigation()

    /// The pane a control has asked the window to show, or `nil` when there is
    /// nothing pending.
    var requestedTab: PreferencesTab?

    private init() {}

    func go(to tab: PreferencesTab) {
        requestedTab = tab
    }
}
