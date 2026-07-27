//
//  CalendarsTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0.
//
//  Modified for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026:
//  earlier passes tidied the provider status/metadata/actions, threaded the live
//  EventKit authorization into the presentation, and added Grant Calendar Access,
//  Force Sync and Re-authenticate Account… affordances. The Preferences UX
//  overhaul (Phase 2) rebuilds the pane around one question — "where do my
//  meetings come from, and is macOS actually syncing them?" — and deletes what
//  could not answer it:
//
//    • the calendar-SOURCE picker. `CalendarSourcePresentation.all` holds exactly
//      one entry, so the pane's most prominent control was a dropdown that could
//      never change anything. It returns automatically when a second provider
//      ships; the stored key is untouched.
//    • the two static onboarding lines ("Uses the macOS Calendar app as the data
//      source", "All configured accounts: …") — boilerplate styled to look like
//      live status, directly under a line that WAS live status.
//    • the duplicate sync caption. `preferences_status_sync_help` said what
//      `preferences_calendar_macos_notice` said, ~60 lines apart in one section.
//      One merged paragraph now lives inside the troubleshooting disclosure.
//    • the Google `Reconnect` / `Change Google Account` actions, unreachable
//      since the Google provider was removed (Onboarding still owns the
//      reconnect path for installs carrying that provider forward).
//    • `AccessDeniedBanner`, declared here and referenced nowhere — a third
//      unused variant of messaging this file already had twice.
//
//  And fixes what stayed: "Refresh now" sends `.forceCalendarSync` (the action
//  that actually nudges macOS) instead of a plain re-fetch; the "Calendars to
//  show" header is always rendered rather than appearing only when the list is
//  empty; the list is grouped by account with the account address under any
//  duplicated name, searchable, with All/None and a live selected count; the
//  empty state carries the action that resolves it; the recovery actions live in
//  a disclosure that opens itself only when macOS reports an error; and the
//  Reminders permission moved here, so every permission is in one place.
//
//  No "Reset this section" here: the pane stores no settings. What it holds is a
//  permission macOS owns and your calendar SELECTION, which is data — and the
//  reset dialog promises, correctly, that your calendars are untouched.
//

import Defaults
import SwiftUI

struct CalendarsTab: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        // Read the live EventKit authorization here (cheap, synchronous) and
        // pass it into the pure presentation so the "Grant calendar access"
        // affordance appears while access is still `.notDetermined`.
        let presentation = PreferencesCalendarPresentation.make(
            from: appModel.state,
            authorizationStatus: PermissionReporter.calendarAuthorizationStatus()
        )

        PreferencesGroupedForm {
            CalendarSyncStatusSection(presentation: presentation)
            CalendarSelectionSection(presentation: presentation)
            RemindersPermissionSection()
            CalendarTroubleshootingSection(presentation: presentation)
        }
    }
}

// MARK: - Sync status

/// One sentence and one timestamp: "Up to date · refreshed 2 minutes ago".
/// The headline and the last-successful-refresh time used to be two rows saying
/// one thing.
private struct CalendarSyncStatusSection: View {
    @EnvironmentObject var appModel: AppModel
    let presentation: PreferencesCalendarPresentation

    var body: some View {
        Section {
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
                    Text(
                        "preferences_calendars_status_refreshed".loco(
                            lastSuccess.formatted(.relative(presentation: .named))
                        )
                    )
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }

                Spacer()

                if presentation.canRequestAccess {
                    // EventKit access is undetermined: request it directly.
                    // Reuse the provider-change path (switchProvider → signIn →
                    // requestFullAccessToEvents) so macOS prompts and the app
                    // registers with TCC.
                    Button("preferences_calendars_grant_access".loco()) {
                        appModel.send(.changeProvider(presentation.activeProvider, signOut: false))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appModel.state.providerChangeInProgress)
                }

                // Renamed from "Force Sync" AND rewired: this used to send
                // `.refreshCalendars` (a plain re-fetch), while the action that
                // actually asks macOS to sync — `.forceCalendarSync` — only ever
                // fired automatically. The most-clicked recovery button now does
                // what its name says.
                Button("preferences_calendars_refresh_now".loco()) {
                    appModel.send(.forceCalendarSync)
                }
                .disabled(appModel.state.providerChangeInProgress)
            }
        }
    }
}

// MARK: - Calendar selection

/// "Calendars to show": always-visible header, per-account groups, a search
/// field, All/None, and the selected count that was computed but never shown.
private struct CalendarSelectionSection: View {
    @EnvironmentObject var appModel: AppModel
    let presentation: PreferencesCalendarPresentation

    @State private var query = ""

    private var items: [CalendarPickerItem] {
        appModel.state.calendars.map {
            CalendarPickerItem(id: $0.id, title: $0.title, source: $0.source, email: $0.email)
        }
    }

    private var groups: [CalendarAccountGroup] {
        CalendarListPresentation.groups(for: items, query: query)
    }

    var body: some View {
        // The header renders unconditionally. It used to appear ONLY when the
        // list was empty, i.e. it vanished the moment it became useful.
        Section(header: Text("preferences_calendars_list_title".loco())) {
            Text("preferences_calendars_list_help".loco())
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if appModel.state.calendars.isEmpty {
                CalendarSelectionEmptyState(presentation: presentation)
            } else {
                HStack(spacing: 8) {
                    TextField(
                        "preferences_calendars_search_placeholder".loco(),
                        text: $query
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)

                    Text(
                        "preferences_calendars_selected_count".loco(
                            presentation.selectedCalendarCount,
                            presentation.availableCalendarCount
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                    Button("preferences_calendars_select_all".loco()) {
                        setSelection(true)
                    }
                    .controlSize(.small)
                    Button("preferences_calendars_select_none".loco()) {
                        setSelection(false)
                    }
                    .controlSize(.small)
                }
            }
        }

        ForEach(groups) { group in
            Section(header: Text(group.titleKey?.loco() ?? group.title)) {
                ForEach(group.rows) { row in
                    if let calendar = calendar(for: row.id) {
                        CalendarRow(calendar: calendar, subtitle: row.subtitle)
                    }
                }
            }
        }
    }

    private func calendar(for id: String) -> MBCalendar? {
        appModel.state.calendars.first { $0.id == id }
    }

    /// All / None act on what is currently on screen, so they stay predictable
    /// while a search narrows the list.
    private func setSelection(_ selected: Bool) {
        for id in CalendarListPresentation.visibleIDs(in: groups) {
            appModel.toggleCalendarSelection(id: id, selected: selected)
        }
    }
}

/// The empty state now carries the action that resolves it, instead of naming a
/// problem and leaving the user to find the fix.
private struct CalendarSelectionEmptyState: View {
    @EnvironmentObject var appModel: AppModel
    let presentation: PreferencesCalendarPresentation

    var body: some View {
        VStack(spacing: 12) {
            Text(presentation.emptyStateTextKey.loco())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if presentation.canRequestAccess {
                Button("preferences_calendars_grant_access".loco()) {
                    appModel.send(.changeProvider(presentation.activeProvider, signOut: false))
                }
                .buttonStyle(.borderedProminent)
                .disabled(appModel.state.providerChangeInProgress)
            } else if presentation.canOpenCalendarSettings {
                Button("preferences_calendars_open_privacy".loco()) {
                    NSWorkspace.shared.open(Links.calendarPreferences)
                }
            } else {
                Button("preferences_calendars_refresh_now".loco()) {
                    appModel.send(.forceCalendarSync)
                }
                .disabled(appModel.state.providerChangeInProgress)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Reminders permission

/// Moved here from the Display tab so permissions are discoverable in one place.
/// It is not the only route: enabling reminders in the Dropdown pane requests the
/// same access as a side effect. This is the pane that asks for it *as* a
/// permission. macOS owns the answer, so once it has been given the switch
/// stops pretending the app can take it back — and a denied prompt leaves a
/// stated denial instead of a switch that silently springs back.
private struct RemindersPermissionSection: View {
    @State private var isGranted = false
    @State private var isDenied = false

    var body: some View {
        Section {
            Toggle("preferences_calendars_reminders_toggle".loco(), isOn: accessBinding)
                .disabled(isGranted || isDenied)

            if isGranted {
                Label(
                    "preferences_calendars_reminders_granted".loco(),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .preferenceIndent()
            } else if isDenied {
                Text("preferences_calendars_reminders_denied".loco())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .preferenceIndent()
            } else {
                // Stated BEFORE the flip, rather than discovered by flipping it.
                Text("preferences_calendars_reminders_help".loco())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .preferenceIndent()
            }
        }
        .onAppear(perform: refresh)
    }

    private var accessBinding: Binding<Bool> {
        Binding(
            get: { isGranted },
            set: { isOn in
                guard isOn else { return }
                Task {
                    _ = await RemindersStore.shared.requestAccess()
                    await MainActor.run { refresh() }
                }
            }
        )
    }

    private func refresh() {
        let status = RemindersStore.shared.authorizationStatus
        isGranted = RemindersStore.isGranted(status)
        isDenied = RemindersStore.isDenied(status)
    }
}

// MARK: - Troubleshooting

/// "Calendar isn't updating?" — the one merged explanation, the staleness
/// signal, the raw error, and the two recovery shortcuts.
///
/// `canReauthenticateAccount` is true for every EventKit install, so the old
/// "Re-authenticate Account…" button sat on screen permanently, including while
/// the status read "Up to date". The recovery actions are now shown only on an
/// error state, and the disclosure opens itself exactly then.
private struct CalendarTroubleshootingSection: View {
    @EnvironmentObject var appModel: AppModel
    let presentation: PreferencesCalendarPresentation

    private var hasError: Bool {
        switch presentation.connectionState {
        case .authRequired, .permissionRequired, .error, .stale: true
        case .initializing, .connected: false
        }
    }

    var body: some View {
        Section {
            PreferencesDisclosure(
                id: "calendars.troubleshooting",
                titleKey: "preferences_calendars_troubleshoot_title",
                opensAutomatically: hasError
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("preferences_calendars_troubleshoot_notice".loco())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // The newest change the app can see. Surfaced, never
                    // auto-judged: if it reads hours old, macOS has stopped
                    // syncing. Hidden when no event carried a modification date.
                    if let lastSyncedChange = presentation.lastSyncedChange {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(
                                "preferences_calendars_last_change".loco(
                                    lastSyncedChange.formatted(.relative(presentation: .named))
                                )
                            )
                            Text("preferences_calendars_last_change_help".loco())
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    if let error = appModel.state.providerHealth.lastErrorDescription {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("preferences_calendars_error_intro".loco())
                            Text(error)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                                .lineLimit(3)
                        }
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    if hasError {
                        HStack {
                            Button("preferences_calendars_open_privacy".loco()) {
                                NSWorkspace.shared.open(Links.calendarPreferences)
                            }
                            // Expired CalDAV/Google/Exchange credentials make
                            // macOS Calendar serve stale data silently; signing
                            // back in there is the real fix.
                            if presentation.canReauthenticateAccount {
                                Button("preferences_calendars_open_internet_accounts".loco()) {
                                    if !NSWorkspace.shared.open(Links.internetAccountsPreferences) {
                                        NSWorkspace.shared.open(Links.systemSettings)
                                    }
                                }
                            }
                            Spacer()
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Shared pieces

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

/// The plain account-grouped list used by the ONBOARDING calendar screen.
/// Preferences uses `CalendarSelectionSection` above, which adds search,
/// All/None, the selected count and duplicate-name disambiguation; first run
/// deliberately stays a plain list.
struct CalendarSectionsView: View {
    let calendars: [MBCalendar]

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

struct CalendarRow: View {
    let calendar: MBCalendar
    /// The account address, shown only when this calendar's name is shared with
    /// another one in the list. The shipping pane listed "Family" twice with no
    /// way to tell the two apart.
    var subtitle: String?
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(calendar.title)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
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
