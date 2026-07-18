//
//  GeneralTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//
//  Modified for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026:
//  remove the StoreKit patronage / Patreon / Buy Me A Coffee monetization from
//  the About card and re-brand it for MeetingBarNG; wrap the About block in the
//  shared PreferencesCard and unify header typography.
//

import SwiftUI

import Defaults
import KeyboardShortcuts

struct GeneralTab: View {
    @Default(.timeFormat) var timeFormat

    var body: some View {
        PreferencesGroupedForm {
            // Clear the grouped-form row chrome for the About row so the
            // PreferencesCard is the sole surface (no card-in-card border).
            Section {
                AboutAppSection()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section(header: Text("preferences_section_general_settings_title".loco())) {
                LaunchAtLoginANDPreferredLanguagePicker()

                // 12/24-hour format affects every surface that renders clock
                // times (dropdown rows, timeline, event details, fullscreen
                // notification), so it lives with the app-wide options rather
                // than under Menu.
                Picker(
                    preferenceLabel("preferences_appearance_menu_time_format_title"),
                    selection: $timeFormat
                ) {
                    Text("preferences_appearance_menu_time_format_12_hour_value".loco())
                        .tag(TimeFormat.am_pm)
                    Text("preferences_appearance_menu_time_format_24_hour_value".loco())
                        .tag(TimeFormat.military)
                }
            }

            Section(header: Text("preferences_section_shortcuts_title".loco())) {
                ShortcutsSection()
            }
        }
    }
}

struct ShortcutsSection: View {
    var body: some View {
        ShortcutRow(
            title: "preferences_general_shortcut_open_menu".loco(),
            recorder: KeyboardShortcuts.Recorder(for: .openMenuShortcut)
        )
        ShortcutRow(
            title: "preferences_general_shortcut_join_next".loco(),
            recorder: KeyboardShortcuts.Recorder(for: .joinEventShortcut)
        )
        ShortcutRow(
            title: "preferences_general_shortcut_create_meeting".loco(),
            recorder: KeyboardShortcuts.Recorder(for: .createMeetingShortcut)
        )
        ShortcutRow(
            title: "preferences_general_shortcut_join_from_clipboard".loco(),
            recorder: KeyboardShortcuts.Recorder(for: .openClipboardShortcut)
        )
        ShortcutRow(
            title: "preferences_general_shortcut_toggle_meeting_name_visibility".loco(),
            recorder: KeyboardShortcuts.Recorder(for: .toggleMeetingTitleVisibilityShortcut)
        )
    }
}

private struct ShortcutRow<Recorder: View>: View {
    let title: String
    let recorder: Recorder

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            recorder
        }
    }
}

struct AboutAppSection: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        // The whole About block is one PreferencesCard, matching the app's
        // Onboarding chrome. A single divider separates identity from the
        // link/diagnostics cluster.
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
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Text("preferences_general_meeting_bar_description".loco())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                Divider()

                // Links + diagnostics.
                HStack(spacing: 16) {
                    Button("GitHub") {
                        Links.github.openInDefaultBrowser()
                    }
                    .buttonStyle(.link)
                    Button("preferences_general_external_contact".loco()) {
                        Links.emailMe.openInDefaultBrowser()
                    }
                    .buttonStyle(.link)
                    Spacer()
                    Button("preferences_status_copy_diagnostics".loco()) {
                        DiagnosticsClipboard.copy(
                            snapshot: DiagnosticsSnapshot(appState: appModel.state)
                        )
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

#Preview() {
    GeneralTab()
        .padding()
        .frame(width: 700, height: 620)
}
