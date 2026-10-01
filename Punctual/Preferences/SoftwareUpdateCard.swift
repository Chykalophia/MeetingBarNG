//
//  SoftwareUpdateCard.swift
//  Punctual
//
//  The "Updates" card on the About pane: Sparkle's automatic-check and
//  automatic-install switches, a manual check, when it last checked, and one
//  plain sentence on what a check sends.
//
//  Original work for Punctual by Peter Krzyzek / Chykalophia, 2026.
//

import SwiftUI

struct SoftwareUpdateCard: View {
    @ObservedObject private var updater = SoftwareUpdater.shared

    var body: some View {
        PreferencesCard("preferences_updates_title".loco()) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    "preferences_updates_auto_check".loco(),
                    isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.setAutomaticallyChecksForUpdates($0) }
                    )
                )
                Toggle(
                    "preferences_updates_auto_install".loco(),
                    isOn: Binding(
                        get: { updater.automaticallyDownloadsUpdates },
                        set: { updater.setAutomaticallyDownloadsUpdates($0) }
                    )
                )
                .disabled(!updater.automaticallyChecksForUpdates)

                HStack {
                    Button("preferences_updates_check_now".loco()) {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)
                    Text(lastCheckedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Text("preferences_updates_privacy_note".loco())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!updater.isAvailable)
        }
    }

    private var lastCheckedText: String {
        guard let date = updater.lastUpdateCheckDate else {
            return "preferences_updates_never_checked".loco()
        }
        let relative = date.formatted(.relative(presentation: .named))
        return "preferences_updates_last_checked".loco(relative)
    }
}
