//
//  PreferencesReset.swift
//  MeetingBarNG
//
//  "Reset this section", and "Reset all settings…" in General ▸ Troubleshooting.
//
//  Before Phase 2 there was no reset anywhere in the app: `Defaults.reset`
//  returned zero hits across 92 keys, so every setting was a one-way door and
//  exploring cost you your configuration. Every one-way door becomes a two-way
//  door — that is what makes eight new panes safe to poke at.
//
//  What a pane owns is NOT declared here. It comes from the hostless
//  `SettingsIndex`, the same source search reads, so a setting that moves pane
//  moves its reset with it and cannot be orphaned.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Defaults
import SwiftUI

enum PreferencesReset {
    /// Restores every stored value the pane owns to its shipped default.
    ///
    /// Deliberately NOT included anywhere in the index, and therefore never
    /// reset: your calendar selection, saved links, browser setups, and the
    /// bookkeeping keys (migration flags, processed-event ledgers). Those are
    /// your data, not settings.
    static func reset(_ tab: PreferencesTab) {
        let keys = SettingsIndex.defaultsKeys(in: tab)
        guard !keys.isEmpty else { return }
        Defaults.reset(keys)
        MeetingBarLogger.preferences.info(
            "Reset section \(tab.rawValue, privacy: .public) (\(keys.count, privacy: .public) keys)"
        )
    }

    /// Restores every setting on every pane.
    static func resetAll() {
        let keys = SettingsIndex.allDefaultsKeys
        Defaults.reset(keys)
        MeetingBarLogger.preferences.info(
            "Reset all settings (\(keys.count, privacy: .public) keys)"
        )
    }
}

/// The trailing "Reset this section…" row every pane ends with.
struct PreferencesResetSection: View {
    let tab: PreferencesTab

    @State private var isConfirming = false

    var body: some View {
        Section {
            HStack {
                Spacer()
                Button("preferences_reset_section_button".loco()) {
                    isConfirming = true
                }
                .controlSize(.small)
            }
        }
        .confirmationDialog(
            "preferences_reset_section_title".loco(tab.titleKey.loco()),
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("preferences_reset_confirm".loco(), role: .destructive) {
                PreferencesReset.reset(tab)
            }
            Button("general_cancel".loco(), role: .cancel) {}
        } message: {
            Text("preferences_reset_section_message".loco())
        }
    }
}

/// "Reset all settings…", which lives only in General ▸ Troubleshooting.
struct PreferencesResetAllButton: View {
    @State private var isConfirming = false

    var body: some View {
        HStack {
            Spacer()
            Button("preferences_reset_all_button".loco()) {
                isConfirming = true
            }
        }
        .confirmationDialog(
            "preferences_reset_all_title".loco(),
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("preferences_reset_confirm".loco(), role: .destructive) {
                PreferencesReset.resetAll()
            }
            Button("general_cancel".loco(), role: .cancel) {}
        } message: {
            Text("preferences_reset_all_message".loco())
        }
    }
}
