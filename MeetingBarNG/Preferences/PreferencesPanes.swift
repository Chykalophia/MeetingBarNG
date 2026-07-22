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
//
// `FiltersTab` has left this file: it is no longer a re-homing of two old
// sections but a pane of its own, so it lives in `FiltersTab.swift` with the
// preset chips, the one Show / Dim / Hide vocabulary and the title-pattern
// tester. The sections it used to compose (`EventsSection`,
// `FilterEventRegexesSection`) are deleted — they had no second reader.

// MARK: - Menu Bar
//
// `MenuBarTab` has left this file too: it is no longer a re-homing of the two
// old menu-bar sections but a pane of its own, so it lives in `MenuBarTab.swift`
// with the preset cards, one block list holding the complete inventory, and
// One line / Two lines. The sections it used to compose (`StatusBarSection`,
// `MenuBarComposerSection`) are deleted — they had no second reader.

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

// MARK: - Joining / Alerts
//
// Both have left this file. They are no longer thin wrappers around the old
// Meetings and Notifications tabs: they own the labels, the disclosures and the
// two halves of the deleted Advanced tab (its meeting-link patterns went to
// `JoiningTab.swift`, its AppleScript hooks to `AlertsTab.swift`).

// MARK: - About & Support

/// Who made this, what changed, and how to get unstuck.
///
/// A pinned sidebar FOOTER item rather than a pane, so it can never become the
/// leftovers bin that "Advanced" was — and so opening Preferences shows a
/// setting rather than credits. It is deliberately NOT a `PreferencesTab` case.
///
/// Not wrapped in `PreferencesGroupedForm`: this is one card, not a settings
/// list, and inside a grouped form it needed three modifiers to fight the row
/// chrome it did not want (`listRowInsets`, `listRowBackground`, and a Section
/// that existed only to hold it).
struct AboutSupportView: View {
    @EnvironmentObject var appModel: AppModel

    /// Drives the transient "Copied" acknowledgement beside the diagnostics
    /// button. Copying to the pasteboard is otherwise completely silent, so the
    /// button read as broken.
    @State private var didCopyDiagnostics = false

    var body: some View {
        ScrollView {
            PreferencesCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        Image("appIconForAbout")
                            .resizable()
                            .frame(width: 72, height: 72)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("MeetingBarNG")
                                    .font(.title2).bold()
                                Text(version)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Text("preferences_about_description".loco())
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }

                    Divider()

                    HStack(spacing: 16) {
                        Button("GitHub") {
                            Links.github.openInDefaultBrowser()
                        }
                        .buttonStyle(.link)
                        Button("preferences_about_contact".loco()) {
                            Links.emailMe.openInDefaultBrowser()
                        }
                        .buttonStyle(.link)
                        Button("preferences_about_whats_new".loco()) {
                            NSApplication.shared.sendAction(
                                #selector(AppDelegate.openChangelogWindow(_:)), to: nil, from: nil
                            )
                        }
                        .buttonStyle(.link)
                        Spacer()
                        if didCopyDiagnostics {
                            Label(
                                "preferences_about_copied".loco(),
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                            .accessibilityAddTraits(.isStaticText)
                        }
                        Button("preferences_about_copy_report".loco()) {
                            copyDiagnostics()
                        }
                        .controlSize(.small)
                    }
                    .animation(.easeOut(duration: 0.15), value: didCopyDiagnostics)
                }
            }
            .padding(20)
        }
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private func copyDiagnostics() {
        Task {
            await DiagnosticsClipboard.copy(
                snapshot: DiagnosticsSnapshot(appState: appModel.state)
            )
            didCopyDiagnostics = true
            try? await Task.sleep(for: .seconds(2))
            didCopyDiagnostics = false
        }
    }
}
