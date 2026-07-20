//
//  CalendarsTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//
//  Modified for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026:
//  tidy the provider status/metadata/actions into a cleaner presentation
//  (presentation logic and calendar toggles unchanged); thread the live
//  EventKit authorization status into the presentation and add a prominent
//  "Grant Calendar Access" button shown while access is still undetermined;
//  surface a "Most recent calendar change" staleness signal and add fix-path
//  affordances (a "Force Sync" button plus a "Re-authenticate Account…" button
//  that opens System Settings ▸ Internet Accounts) with a caption explaining the
//  app shows what macOS Calendar has synced.
//

import Defaults
import SwiftUI

struct CalendarsTab: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        // Read the live EventKit authorization here (cheap, synchronous) and
        // pass it into the pure presentation so the "Grant Calendar Access"
        // affordance appears while access is still `.notDetermined`.
        let presentation = PreferencesCalendarPresentation.make(
            from: appModel.state,
            authorizationStatus: PermissionReporter.calendarAuthorizationStatus()
        )

        PreferencesGroupedForm {
            Section(header: Text("preferences_calendar_source_title".loco())) {
                ProviderPicker()

                // Status headline: a prominent, tinted state line with the last
                // successful-refresh time trailing it.
                HStack(spacing: 6) {
                    Label(
                        presentation.statusTextKey.loco(),
                        systemImage: statusSystemImage(presentation.statusTone)
                    )
                    .foregroundStyle(statusColor(presentation.statusTone))
                    .font(.subheadline.weight(.medium))
                    if let lastSuccess = appModel.state.providerHealth.lastSuccessfulRefresh {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(lastSuccess.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    Spacer()
                }

                // Staleness signal: the newest calendar change we saw synced. If
                // this reads far older than the user knows their calendar to be,
                // macOS Calendar's own sync has stalled — surfaced, not judged.
                // Hidden entirely when no event carried a modification date.
                if let lastSyncedChange = presentation.lastSyncedChange {
                    HStack(spacing: 6) {
                        Text("preferences_status_last_change".loco(
                            lastSyncedChange.formatted(.relative(presentation: .named))
                        ))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        Spacer()
                    }
                }

                // Provider metadata.
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        presentation.providerDataSourceKey.loco(),
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    Label(
                        presentation.providerAccountScopeKey.loco(),
                        systemImage: "person.2"
                    )
                }
                .foregroundStyle(.secondary)
                .font(.caption)

                if let error = appModel.state.providerHealth.lastErrorDescription {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(3)
                }

                // Actions.
                HStack {
                    Spacer()
                    if presentation.canRequestAccess {
                        // EventKit access is undetermined: request it directly.
                        // Reuse the provider-change path (switchProvider → signIn
                        // → requestFullAccessToEvents) so macOS prompts and the
                        // app registers with TCC.
                        Button("preferences_status_grant_access".loco()) {
                            appModel.send(
                                .changeProvider(presentation.activeProvider, signOut: false))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appModel.state.providerChangeInProgress)
                    }
                    if presentation.canReconnect {
                        Button("preferences_status_reconnect".loco()) {
                            appModel.send(
                                .changeProvider(presentation.activeProvider, signOut: true))
                        }
                        .disabled(appModel.state.providerChangeInProgress)
                    }
                    if presentation.canReauthenticateAccount {
                        // Expired CalDAV/Google/Exchange credentials cause macOS
                        // Calendar to silently serve stale data. Re-signing in
                        // (System Settings ▸ Internet Accounts) is the real fix.
                        Button("preferences_status_fix_account".loco()) {
                            if !NSWorkspace.shared.open(Links.internetAccountsPreferences) {
                                NSWorkspace.shared.open(Links.systemSettings)
                            }
                        }
                    }
                    if presentation.canOpenCalendarSettings {
                        Button("preferences_status_open_calendar_settings".loco()) {
                            NSWorkspace.shared.open(Links.calendarPreferences)
                        }
                    }
                    // Force Sync always re-fetches (and updates the "most recent
                    // change" line) so the user gets immediate feedback; the
                    // automatic menu-open/wake/unlock nudges do the aggressive
                    // macOS refreshSources() pass.
                    Button("preferences_status_force_sync".loco()) {
                        appModel.send(.refreshCalendars)
                    }
                    .disabled(appModel.state.providerChangeInProgress)
                }

                // The app shows what macOS Calendar has synced. If events look
                // outdated, macOS Calendar may need to re-sync or the account
                // re-authenticated — spell that out so the buttons make sense.
                Text("preferences_status_sync_help".loco())
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if appModel.state.calendars.isEmpty {
                Section(header: Text("preferences_calendars_select_calendars_title".loco())) {
                    CalendarPreferencesEmptyState(presentation: presentation)
                }
            } else {
                CalendarSectionsView(calendars: appModel.state.calendars)
            }
        }
    }

}

private struct CalendarPreferencesEmptyState: View {
    @EnvironmentObject var appModel: AppModel
    let presentation: PreferencesCalendarPresentation

    var body: some View {
        VStack(spacing: 10) {
            Text(emptyStateText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private var emptyStateText: String {
        presentation.emptyStateTextKey.loco()
    }
}

private func statusSystemImage(_ tone: PreferencesStatusTone) -> String {
    switch tone {
    case .neutral: "circle"
    case .success: "checkmark.circle.fill"
    case .warning: "exclamationmark.triangle.fill"
    case .error: "xmark.circle.fill"
    }
}

private func statusColor(_ tone: PreferencesStatusTone) -> Color {
    switch tone {
    case .neutral: .secondary
    case .success: .green
    case .warning: .orange
    case .error: .red
    }
}

struct CalendarSectionsView: View {
    let calendars: [MBCalendar]

    // 1. Compute once, with explicit types
    private var grouped: [String: [MBCalendar]] {
        Dictionary(grouping: calendars, by: \.source)
    }

    private var sources: [String] {
        grouped.keys.sorted()
    }

    var body: some View {
        ForEach(sources, id: \.self) { source in
            Section(header: Text(source)) {
                ForEach(grouped[source]!, id: \.id) { cal in
                    CalendarRow(calendar: cal)
                }
            }
        }
    }
}

struct ProviderPicker: View {
    @EnvironmentObject var appModel: AppModel
    @State private var picker = EventStoreProvider.macOSEventKit

    var body: some View {
        Picker("access_screen_provider_picker_label".loco(), selection: $picker) {
            ForEach(CalendarSourcePresentation.all) { source in
                Text(source.titleKey.loco()).tag(source.provider)
            }
        }
        .onChange(of: picker) { provider in
            guard ProviderPickerSelectionPolicy.shouldRequestChange(
                selectedProvider: provider,
                activeProvider: appModel.state.activeProvider,
                providerChangeInProgress: appModel.state.providerChangeInProgress
            ) else { return }
            appModel.send(.changeProvider(provider, signOut: false))
        }
        .disabled(appModel.state.providerChangeInProgress)
        .onAppear {
            picker = appModel.state.activeProvider
        }
        .onChange(of: appModel.state.activeProvider) { provider in
            picker = provider
        }
        .onChange(of: appModel.state.providerChangeInProgress) { inProgress in
            picker = ProviderPickerSelectionPolicy.synchronizedSelection(
                currentSelection: picker,
                activeProvider: appModel.state.activeProvider,
                providerChangeInProgress: inProgress
            )
        }

        if appModel.state.activeProvider == .googleCalendar {
            HStack {
                Spacer()
                Button("preferences_calendars_provider_gcalendar_change_account".loco()) {
                    appModel.send(.changeProvider(.googleCalendar, signOut: true))
                }
                .disabled(appModel.state.providerChangeInProgress)
            }
        }
    }
}

struct AccessDeniedBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("access_screen_access_screen_access_denied_go_to_title".loco())
            Button("access_screen_access_denied_system_preferences_button".loco()) {
                NSWorkspace.shared.open(Links.calendarPreferences)
            }
            Text("access_screen_access_denied_relaunch_title".loco())
        }
        .padding(.top, 8)
    }
}

struct CalendarRow: View {
    let calendar: MBCalendar
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { appModel.state.selectedCalendarIDs.contains(calendar.id) },
                set: { appModel.toggleCalendarSelection(id: calendar.id, selected: $0) }
            )
        ) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(calendar.color))
                    .frame(width: 10, height: 10)
                Text(calendar.title)
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    List {
        CalendarSectionsView(calendars: [
            MBCalendar(
                title: "Calendar #1", id: "1", source: "Source #1", email: nil, color: .brown)
        ])

        CalendarSectionsView(calendars: [
            MBCalendar(title: "Calendar #2", id: "2", source: "Source #2", email: nil, color: .blue)
        ])
    }.listStyle(.sidebar)
        .frame(width: 300, height: 200)
}
