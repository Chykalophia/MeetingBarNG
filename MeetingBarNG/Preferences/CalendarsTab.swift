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
//    • the calendar-SOURCE picker. `CalendarSourcePresentation.all` held exactly
//      one entry, so the pane's most prominent control was a dropdown that could
//      never change anything. It is now back as a TOGGLE PER SOURCE (multi-source,
//      2026), rendered only when a second source is genuinely available.
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
            CalendarSourceSection(presentation: presentation)
            CalendarSyncStatusSection(presentation: presentation)
            CalendarSelectionSection(presentation: presentation)
            RemindersPermissionSection()
            CalendarTroubleshootingSection(presentation: presentation)
        }
    }
}

// MARK: - Calendar source

/// Where meetings come from — now a set, not a choice.
///
/// The Phase 2 overhaul deleted the picker because
/// `CalendarSourcePresentation.all` held exactly one entry, making it a dropdown
/// that could never change anything. It came back as a picker when the Google
/// provider was restored, and is now a toggle per source: the two are not
/// mutually exclusive, and forcing a choice between them meant anyone with both
/// an Exchange calendar in Calendar.app and a Google work account could only
/// ever see half their day. Renders only when a second source is genuinely
/// available, so a build without Google credentials looks exactly as it did.
private struct CalendarSourceSection: View {
    @EnvironmentObject var appModel: AppModel
    let presentation: PreferencesCalendarPresentation

    var body: some View {
        let sources = CalendarSourcePresentation.all
        if sources.count > 1 {
            Section {
                // A toggle per source rather than a picker. Sources are no
                // longer mutually exclusive: someone with an Exchange calendar
                // in Calendar.app and a Google work account needs both, and the
                // picker made that a choice between halves of their day.
                ForEach(sources) { source in
                    CalendarSourceToggle(
                        source: source,
                        isConnected: presentation.connectedProviders.contains(source.provider),
                        canDisconnect: presentation.connectedProviders.count > 1,
                        failure: presentation.degradedSources
                            .first { $0.provider == source.provider }
                    )
                }

                Text("preferences_calendars_source_help".loco())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One connected source: a toggle, its description, and — when it is failing
/// while another source still works — the reason and a way to reconnect.
private struct CalendarSourceToggle: View {
    @EnvironmentObject var appModel: AppModel
    let source: CalendarSourcePresentation
    let isConnected: Bool
    let canDisconnect: Bool
    let failure: CalendarSourceFailure?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(source.titleKey.loco(), isOn: connectionBinding)
                .disabled(appModel.state.providerChangeInProgress || !canToggle)

            Text(source.descriptionKey.loco())
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Google needs an OAuth client before it can be switched on at all.
            // The credentials editor lives on the row rather than behind the
            // toggle, because when no client exists the toggle is exactly what
            // cannot be used.
            if source.provider == .googleCalendar {
                GoogleOAuthClientSection(hasClient: hasGoogleClient)
            }

            // A source that failed while the other kept working would otherwise
            // just show fewer meetings, with nothing on screen saying why.
            if let failure {
                HStack(spacing: 6) {
                    Label(failure.errorDescription, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                    if failure.authRequired {
                        Button("preferences_status_reconnect".loco()) {
                            appModel.send(.changeProvider(source.provider, signOut: true))
                        }
                        .controlSize(.small)
                        .disabled(appModel.state.providerChangeInProgress)
                    }
                }
            }
        }
    }

    /// The last connected source cannot be switched off — with none connected
    /// the app fetches nothing and looks broken rather than configured. Google
    /// additionally cannot be switched ON without a client to sign in with.
    private var canToggle: Bool {
        guard !isConnected else { return canDisconnect }
        return source.provider != .googleCalendar || hasGoogleClient
    }

    private var hasGoogleClient: Bool { GoogleOAuthConfig.effectiveClient != nil }

    /// Connecting runs sign-in for that source and ADDS it. Disconnecting keeps
    /// its credentials (`signOut: false`) so re-enabling is not a fresh OAuth
    /// round trip; signing out stays a separate, deliberate action.
    private var connectionBinding: Binding<Bool> {
        Binding(
            get: { isConnected },
            set: { shouldConnect in
                guard shouldConnect != isConnected else { return }
                if shouldConnect {
                    appModel.send(.changeProvider(source.provider, signOut: false))
                } else {
                    appModel.send(.disconnectProvider(source.provider))
                }
            }
        )
    }
}

/// An account header that also names the SOURCE its calendars came from.
///
/// The account name alone was ambiguous the moment both sources could be
/// connected: macOS Calendar reports a Google account as a source literally
/// named "Google", while the direct provider reports the same account by its
/// address. Two groups, no way to tell which was which — or that they were the
/// same calendars arriving twice.
private struct CalendarAccountHeader: View {
    let group: CalendarAccountGroup

    var body: some View {
        HStack(spacing: 6) {
            Text(group.titleKey?.loco() ?? group.title)

            Text(group.providerTitleKey.loco())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    Capsule().fill(Color.secondary.opacity(0.15))
                )
                .accessibilityLabel(
                    "preferences_calendars_account_source".loco(group.providerTitleKey.loco())
                )
        }
    }
}

/// Bring-your-own Google OAuth client.
///
/// A shipped client id is extractable from any native binary — that is inherent
/// to native OAuth, not a flaw in this app, and PKCE is why it is safe (see
/// `GoogleOAuthClient`). What an extracted id actually costs is API quota and
/// the ability to put this app's name on a consent screen. So the point of this
/// section is not secrecy: it is that anyone who would rather run on THEIR
/// project's quota, under THEIR consent screen — or whose employer requires it —
/// can, without building from source.
///
/// It is also the only way to use Google at all in a build that ships no
/// credentials, which is why it renders even when the toggle above is disabled.
private struct GoogleOAuthClientSection: View {
    let hasClient: Bool

    @Default(.googleUseUserOAuthClient) private var useOwnClient
    @State private var clientID: String = GoogleUserOAuthClientStore.clientID
    @State private var clientSecret: String = GoogleUserOAuthClientStore.clientSecret

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("preferences_calendars_google_own_client".loco(), isOn: ownClientBinding)

            if useOwnClient {
                TextField(
                    "preferences_calendars_google_client_id".loco(),
                    text: $clientID
                )
                .textFieldStyle(.roundedBorder)
                .onChange(of: clientID) { _, newValue in
                    GoogleUserOAuthClientStore.clientID = newValue
                }

                SecureField(
                    "preferences_calendars_google_client_secret".loco(),
                    text: $clientSecret
                )
                .textFieldStyle(.roundedBorder)
                .onChange(of: clientSecret) { _, newValue in
                    GoogleUserOAuthClientStore.clientSecret = newValue
                }

                // Only the id can be judged locally. Whether the client actually
                // works is Google's answer to give, at sign-in.
                if !clientID.isEmpty, !GoogleOAuthClientResolver.isValidClientID(clientID) {
                    Label(
                        "preferences_calendars_google_client_id_invalid".loco(),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                Text("preferences_calendars_google_own_client_help".loco())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !hasClient {
                // No shipped client and no supplied one: say so, rather than
                // leaving a disabled toggle with no explanation.
                Label(
                    "preferences_calendars_google_no_client".loco(),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 20)
    }

    /// Turning this OFF forgets the entered credentials rather than leaving a
    /// secret sitting in the Keychain for a client no longer in use.
    private var ownClientBinding: Binding<Bool> {
        Binding(
            get: { useOwnClient },
            set: { enabled in
                useOwnClient = enabled
                if !enabled {
                    GoogleUserOAuthClientStore.clear()
                    clientID = ""
                    clientSecret = ""
                }
            }
        )
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
            CalendarPickerItem(
                id: $0.id,
                title: $0.title,
                source: $0.source,
                email: $0.email,
                provider: $0.provider.sourceKind
            )
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
            Section(header: CalendarAccountHeader(group: group)) {
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
            appModel.toggleCalendarSelection(
                id: id, selected: selected, provider: calendar(for: id)?.provider)
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
    /// True from the moment the switch is flipped until macOS answers.
    ///
    /// Without it the switch could not move. The binding's `get` returned
    /// `isGranted`, which cannot change until the async request completes, so
    /// SwiftUI redrew the switch in its old position on the very next frame —
    /// the click read as nothing happening at all, with no animation and no
    /// hint that a request was in flight.
    @State private var isRequesting = false

    var body: some View {
        Section {
            Toggle("preferences_calendars_reminders_toggle".loco(), isOn: accessBinding)
                // Off once macOS owns the answer, and while it is being asked —
                // a second flip during the prompt cannot do anything useful.
                .disabled(isGranted || isDenied || isRequesting)

            if isRequesting {
                Label(
                    "preferences_calendars_reminders_requesting".loco(),
                    systemImage: "hourglass"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .preferenceIndent()
            } else if isGranted {
                Label(
                    "preferences_calendars_reminders_granted".loco(),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .preferenceIndent()
            } else if isDenied {
                VStack(alignment: .leading, spacing: 6) {
                    Text("preferences_calendars_reminders_denied".loco())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // macOS will not prompt twice, so a denial with no route
                    // back is a dead end: a permanently off switch that cannot
                    // be moved and says nothing about where it can be.
                    Button("preferences_calendars_reminders_open_settings".loco()) {
                        NSWorkspace.shared.open(Links.remindersPreferences)
                    }
                    .controlSize(.small)
                }
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
        .animation(.default, value: isGranted)
        .animation(.default, value: isDenied)
        .animation(.default, value: isRequesting)
        .onAppear(perform: refresh)
        // The answer lives in System Settings, so it can change while this pane
        // is open — via the button above, or from anywhere else. Re-reading on
        // activation keeps the switch from contradicting the system.
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            refresh()
        }
    }

    private var accessBinding: Binding<Bool> {
        Binding(
            // `isRequesting` is what lets the switch move immediately and STAY
            // moved while macOS's prompt is up.
            get: { isGranted || isRequesting },
            set: { isOn in
                guard isOn, !isRequesting, !isGranted, !isDenied else { return }
                isRequesting = true
                Task {
                    _ = await RemindersStore.shared.requestAccess()
                    await MainActor.run {
                        isRequesting = false
                        refresh()
                    }
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
                set: {
                    appModel.toggleCalendarSelection(
                        id: calendar.id, selected: $0, provider: calendar.provider)
                }
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
