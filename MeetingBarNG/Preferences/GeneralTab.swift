//
//  GeneralTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0.
//
//  Modified for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026: the StoreKit
//  patronage / Patreon / Buy Me A Coffee monetization was removed from the About
//  card and the card re-branded; Preferences UX overhaul Phase 0 gave "Copy
//  diagnostics" a visible confirmation. Phase 2 makes this pane the app itself
//  and nothing else:
//
//    • the About card MOVED to the About & Support sidebar footer. Opening
//      Preferences must not show credits before a setting — and the card needed
//      three modifiers to fight the grouped form it was sitting in.
//    • `LaunchAtLoginANDPreferredLanguagePicker` is dissolved (its name literally
//      contained "AND"): the login toggle is rendered here directly.
//    • the LANGUAGE PICKER is DELETED. It offered 16 languages against one
//      maintained catalog (en 659 lines, de 391, ja 410); `ukrainian` mapped to
//      "ua" while the shipped bundle is `uk.lproj`, so choosing it silently did
//      nothing; and seven shipped bundles (bg, hu, ko, ta, pt, zh-Hans, enm) had
//      no entry at all. The app follows macOS instead. This is the one deletion
//      in the overhaul that removes a real — if already broken — capability, so
//      it is flagged rather than buried: the `preferredLanguage` Defaults key is
//      RETAINED and still applied at launch (`I18N.changeLanguage(to:)`, driven
//      from `StatusBarItemController`), so restoring the control means putting a
//      picker back, not rebuilding a feature. Do that when the catalogs are
//      maintained and `AppLanguage.ukrainian` names the bundle that exists.
//    • the ten shortcut rows lose their trailing colons and their engineer names
//      ("Open command bar:" → "Open the search bar"), and are sorted into four
//      labelled groups, because a flat list of ten hotkeys is a list nobody
//      reads.
//    • Troubleshooting held a "Use the classic macOS menu instead" switch until
//      that menu was deleted (`9c178efd`). Only "Reset all settings" remains.
//

import SwiftUI

import Defaults
import KeyboardShortcuts
import LaunchAtLogin

struct GeneralTab: View {
    @Default(.timeFormat) var timeFormat
    @Default(.locationAutocompleteEnabled) var locationAutocompleteEnabled

    var body: some View {
        PreferencesGroupedForm {
            Section {
                // The one setting in the app that turns on a network request.
                // Its help text names what leaves the Mac rather than describing
                // the benefit — someone who cares needs the fact, not the pitch.
                Toggle(
                    preferenceLabel("preferences_general_location_autocomplete_toggle"),
                    isOn: $locationAutocompleteEnabled
                )
                Text("preferences_general_location_autocomplete_help".loco())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                LaunchAtLogin.Toggle {
                    Text("preferences_general_login_toggle".loco())
                }

                Picker(
                    "preferences_general_time_format_title".loco(),
                    selection: $timeFormat
                ) {
                    Text("preferences_general_time_format_12_hour".loco())
                        .tag(TimeFormat.am_pm)
                    Text("preferences_general_time_format_24_hour".loco())
                        .tag(TimeFormat.military)
                }
                .annotation("preferences_general_time_format_help")
            }

            ShortcutsSection()

            TroubleshootingSection()
        }
    }
}

// MARK: - Keyboard shortcuts

/// Ten hotkeys in four groups named for what the user is trying to do, with a
/// description on every row whose label cannot carry the whole answer ("Open the
/// calendar window" — *MeetingBarNG's own month view, not Apple's Calendar app*).
struct ShortcutsSection: View {
    var body: some View {
        Section(header: Text("preferences_general_shortcuts_title".loco())) {
            ShortcutGroupLabel(titleKey: "preferences_general_shortcuts_open_group")
            ShortcutRow(
                titleKey: "preferences_general_shortcut_open_dropdown",
                recorder: KeyboardShortcuts.Recorder(for: .openMenuShortcut)
            )
            ShortcutRow(
                titleKey: "preferences_general_shortcut_open_calendar_window",
                helpKey: "preferences_general_shortcut_open_calendar_window_help",
                recorder: KeyboardShortcuts.Recorder(for: .calendarShortcut)
            )
            ShortcutRow(
                titleKey: "preferences_general_shortcut_open_search_bar",
                helpKey: "preferences_general_shortcut_open_search_bar_help",
                recorder: KeyboardShortcuts.Recorder(for: .commandBarShortcut)
            )
            ShortcutRow(
                titleKey: "preferences_general_shortcut_open_world_clock",
                recorder: KeyboardShortcuts.Recorder(for: .worldClockShortcut)
            )
        }

        Section {
            ShortcutGroupLabel(titleKey: "preferences_general_shortcuts_join_group")
            ShortcutRow(
                titleKey: "preferences_general_shortcut_join_next",
                recorder: KeyboardShortcuts.Recorder(for: .joinEventShortcut)
            )
            ShortcutRow(
                titleKey: "preferences_general_shortcut_join_clipboard",
                recorder: KeyboardShortcuts.Recorder(for: .openClipboardShortcut)
            )
            ShortcutRow(
                titleKey: "preferences_general_shortcut_camera_check",
                recorder: KeyboardShortcuts.Recorder(for: .cameraPreviewShortcut)
            )
        }

        Section {
            ShortcutGroupLabel(titleKey: "preferences_general_shortcuts_make_group")
            ShortcutRow(
                titleKey: "preferences_general_shortcut_create_meeting",
                helpKey: "preferences_general_shortcut_create_meeting_help",
                recorder: KeyboardShortcuts.Recorder(for: .createMeetingShortcut)
            )
            ShortcutRow(
                titleKey: "preferences_general_shortcut_new_event",
                recorder: KeyboardShortcuts.Recorder(for: .newEventShortcut)
            )
        }

        Section {
            ShortcutGroupLabel(titleKey: "preferences_general_shortcuts_privacy_group")
            ShortcutRow(
                titleKey: "preferences_general_shortcut_hide_title",
                helpKey: "preferences_general_shortcut_hide_title_help",
                recorder: KeyboardShortcuts.Recorder(for: .toggleMeetingTitleVisibilityShortcut)
            )
        }
    }
}

private struct ShortcutGroupLabel: View {
    let titleKey: String

    var body: some View {
        Text(titleKey.loco())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct ShortcutRow<Recorder: View>: View {
    let titleKey: String
    var helpKey: String?
    let recorder: Recorder

    var body: some View {
        LabeledContent {
            recorder
        } label: {
            Text(titleKey.loco())
            if let helpKey {
                Text(helpKey.loco())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Troubleshooting

/// The two ways out. Hidden by scope, not by rarity: both are things you reach
/// for when something has gone wrong, and neither is a display preference.
private struct TroubleshootingSection: View {
    var body: some View {
        Section {
            PreferencesDisclosure(
                id: "general.troubleshooting",
                titleKey: "preferences_general_troubleshooting_title"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    PreferencesResetAllButton()
                }
                .padding(.top, 4)
            }
        }
    }
}

#Preview() {
    GeneralTab()
        .padding()
        .frame(width: 700, height: 620)
}
