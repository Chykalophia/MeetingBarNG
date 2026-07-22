//
//  PreferencesPanes.swift
//  MeetingBarNG
//
//  The eight panes of the Phase 2 Preferences IA, assembled from the section
//  views that already existed. The old tabs were containers whose names carried
//  no routing information — "Display" and "Events" in particular could not be
//  told apart, because in a calendar app every setting is about displaying
//  events. The sections themselves were fine; only their homes were wrong.
//
//  So this file is deliberately thin: it re-homes existing sections under the
//  routing rule, and does NOT rewrite their internals. Content refinement (the
//  label pass, per-pane reset UI, and the sections that still need splitting
//  apart) follows pane by pane, so each step leaves a working app.
//
//  The routing rule, applied with zero exceptions:
//    which meetings exist        → Filters
//    how one surface draws them  → that surface's pane
//    what happens when you act   → Joining / Alerts
//    the app itself              → General
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026
//  (Preferences UX overhaul, Phase 2 — the IA restructure).
//

import SwiftUI

// MARK: - Filters

/// The one place that decides which meetings exist — in the menu bar, the
/// dropdown and the calendar window alike. Holds no styling options at all;
/// that separation is the whole point of splitting it out of "Events".
struct FiltersTab: View {
    var body: some View {
        PreferencesGroupedForm {
            EventsSection()
            FilterEventRegexesSection()
        }
    }
}

// MARK: - Menu Bar

/// What you see in the macOS menu bar all day: the classic icon/title/time
/// controls plus the composable token builder.
struct MenuBarTab: View {
    var body: some View {
        PreferencesGroupedForm {
            StatusBarSection()
            MenuBarComposerSection()
        }
    }
}

// MARK: - Dropdown

/// What you see when you click MeetingBarNG. Keeps the two-pane layout: the
/// settings scroll on the left, the live preview stays pinned on the right.
///
/// Phase 3 replaces `DisplayPreviewPane` with the real `DropdownPanelView`
/// rendered against fixtures — it is a second, drifting implementation of the
/// thing it previews (its agenda row is 76pt where the real one is 66pt).
struct DropdownTab: View {
    var body: some View {
        HStack(spacing: 0) {
            PreferencesGroupedForm {
                DropdownComposerSection()
                DropdownDisplaySection()
                EventDetailSection()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            DisplayPreviewPane()
                .frame(width: 340)
                .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Calendar Window

/// The month/week window MeetingBarNG opens — not Apple's Calendar app.
///
/// Deliberately thin for now (owner decision 4 kept "Dim weekends" in
/// Preferences as a display option, and the routing rule then earns this
/// surface its own pane). Phase 6 fills it out with first day of the week,
/// week numbers, and the per-day event cap.
struct CalendarWindowTab: View {
    var body: some View {
        PreferencesGroupedForm {
            CalendarWindowDisplaySection()
        }
    }
}

// MARK: - Joining

/// What happens when you click Join, and where new meetings get created.
struct JoiningTab: View {
    var body: some View {
        MeetingsTab()
    }
}

// MARK: - Alerts

/// When MeetingBarNG interrupts you.
struct AlertsTab: View {
    var body: some View {
        NotificationsTab()
    }
}

// MARK: - About & Support

/// A pinned sidebar FOOTER item rather than a pane, so it can never become the
/// leftovers bin that "Advanced" was.
struct AboutSupportView: View {
    var body: some View {
        PreferencesGroupedForm {
            AboutAppSection()
        }
    }
}
