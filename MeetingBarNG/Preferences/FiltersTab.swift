//
//  FiltersTab.swift
//  MeetingBarNG
//
//  The Filters pane (Preferences UX overhaul, Phase 2): the ONE place that
//  decides which meetings exist — in the menu bar, the dropdown and the calendar
//  window alike.
//
//  The pane is named for the only job it does. Owner decision 1 renamed it from
//  "Which Meetings" to "Filters" *conditional on it being only about filtering*,
//  so no styling option may ever land here: every row below removes or
//  de-emphasises meetings, and nothing on it changes how one surface draws them.
//  That is also how the old Display-vs-Events confusion is resolved — a setting
//  is never split into a filter half on one pane and a style half on another.
//
//  What lives here, in order:
//    1. A permanent scope banner. These choices apply everywhere.
//    2. Look ahead — the fetch window, so "Today" means tomorrow's meetings are
//       never loaded at all.
//    3. Merge duplicates across calendars.
//    4. Preset chips, resolved by the hostless `FilterPreset` (FilterPresets.swift).
//    5. Under "Pick them one by one": the seven per-kind rows, one vocabulary.
//    6. The meeting happening now.
//    7. Hide meetings whose title matches a pattern, with a live tester that runs
//       the SAME `EventFiltering.titleIsFilteredOut` the filter itself runs.
//    8. Reset this section.
//
//  Stored key NAMES are unchanged by the re-home, so nobody's configuration
//  resets: `showEventsForPeriod`, `deduplicateEvents`, `allDayEvents`,
//  `nonAllDayEvents`, `personalEventsAppereance`, `showPendingEvents`,
//  `showTentativeEvents`, `declinedEventsAppereance`, `pastEventsAppereance`,
//  `hideFinishedEventsInMenu`, `ongoingEventVisibility`, `filterEventRegexes`.
//
//  The per-kind rows and the look-ahead / merge-duplicates controls descend from
//  `EventsSection` (EventsTab.swift, moved there from AppearanceTab.swift),
//  originally:
//    Created by Andrii Leitsius on 13.01.2021.
//    Copyright © 2021 Andrii Leitsius. All rights reserved.
//  Licensed under the Apache License, Version 2.0. Modified for MeetingBarNG by
//  Peter Krzyzek / Chykalophia, 2026: re-homed onto the Filters pane, collapsed
//  behind preset chips and one Show / Dim / Hide vocabulary, merged
//  `hideFinishedEventsInMenu` into the ended-meetings row, absorbed the Advanced
//  tab's title-pattern list with a live tester, and stated the menu-bar coupling
//  that "Dim" has always had and never disclosed.
//

import Defaults
import SwiftUI

struct FiltersTab: View {
    // Fetch window + de-duplication.
    @Default(.showEventsForPeriod) private var showEventsForPeriod
    @Default(.deduplicateEvents) private var deduplicateEvents

    // The seven per-kind rows. `pastEventsAppereance` and
    // `hideFinishedEventsInMenu` are ONE row; see `endedVisibility`.
    @Default(.allDayEvents) private var allDayEvents
    @Default(.nonAllDayEvents) private var nonAllDayEvents
    @Default(.personalEventsAppereance) private var personalEventsAppereance
    @Default(.showPendingEvents) private var showPendingEvents
    @Default(.showTentativeEvents) private var showTentativeEvents
    @Default(.declinedEventsAppereance) private var declinedEventsAppereance
    @Default(.pastEventsAppereance) private var pastEventsAppereance
    @Default(.hideFinishedEventsInMenu) private var hideFinishedEventsInMenu

    // The meeting happening now, and the title patterns.
    @Default(.ongoingEventVisibility) private var ongoingEventVisibility
    @Default(.filterEventRegexes) private var filterEventRegexes

    // Written by `PreferencesDisclosure`; read here so the "Custom" chip can
    // reveal the rows it names.
    @Default(.preferencesExpandedDisclosures) private var expandedDisclosures

    /// Typed here, never stored: the tester must work before you save anything.
    @State private var patternTestTitle = ""

    private static let customDisclosureID = "filters.custom"

    var body: some View {
        PreferencesGroupedForm {
            scopeBanner
            fetchSection
            presetSection
            customSection
            ongoingSection
            titlePatternSection
            PreferencesResetSection(tab: .filters)
        }
        .onAppear(perform: retireDeletedOptionValues)
    }

    // MARK: - Scope

    /// Permanent, not dismissible. Every other pane in the window is scoped to
    /// one surface, so the one pane that is not has to say so on sight.
    private var scopeBanner: some View {
        Section {
            PreferenceCallout(
                systemImage: "line.3.horizontal.decrease.circle.fill",
                message: "preferences_filters_scope_banner".loco(),
                tint: .accentColor
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - What gets loaded at all

    private var fetchSection: some View {
        Section {
            // This is the FETCH window (`CalendarRepository.calendarDateRange`),
            // not a display filter — hence the help line: on "Today", tomorrow's
            // meetings are never loaded, so nothing downstream can show them.
            Picker(
                "preferences_filters_look_ahead_title".loco(),
                selection: $showEventsForPeriod
            ) {
                Text("preferences_filters_look_ahead_today".loco())
                    .tag(ShowEventsForPeriod.today)
                Text("preferences_filters_look_ahead_today_tomorrow".loco())
                    .tag(ShowEventsForPeriod.today_n_tomorrow)
            }
            helpText("preferences_filters_look_ahead_help")

            Toggle("preferences_filters_dedup_toggle".loco(), isOn: $deduplicateEvents)
            helpText("preferences_filters_dedup_help")
        }
    }

    // MARK: - Presets

    /// One-click starting points. The selected chip is DERIVED from the stored
    /// values (`FilterPreset.detect`), so "Custom" is a label rather than a mode
    /// you can get stuck in or lose when the window closes.
    private var presetSection: some View {
        Section(header: Text("preferences_filters_preset_title".loco())) {
            Picker("", selection: presetSelection) {
                ForEach(FilterPreset.allCases, id: \.self) { preset in
                    Text(preset.titleKey.loco()).tag(preset)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    /// Reads the chip from the stored values; writing a named chip writes all
    /// eight values at once. Picking "Custom" stores NOTHING — it opens the row
    /// list it names, which is the only thing "custom" can honestly mean.
    private var presetSelection: Binding<FilterPreset> {
        Binding(
            get: { FilterPreset.detect(storedFilterValues) },
            set: { preset in
                guard preset != .custom else {
                    revealCustomRows()
                    return
                }
                apply(preset)
            }
        )
    }

    /// The stored values in the hostless module's raw-string vocabulary.
    private var storedFilterValues: [String: String] {
        [
            FilterDefaultsKey.allDay: allDayEvents.rawValue,
            FilterDefaultsKey.noLink: nonAllDayEvents.rawValue,
            FilterDefaultsKey.solo: personalEventsAppereance.rawValue,
            FilterDefaultsKey.pending: showPendingEvents.rawValue,
            FilterDefaultsKey.tentative: showTentativeEvents.rawValue,
            FilterDefaultsKey.declined: declinedEventsAppereance.rawValue,
            FilterDefaultsKey.ended: pastEventsAppereance.rawValue,
            FilterDefaultsKey.hideFinished: String(hideFinishedEventsInMenu)
        ]
    }

    private func apply(_ preset: FilterPreset) {
        let values = preset.values
        guard !values.isEmpty else { return }

        if let raw = values[FilterDefaultsKey.allDay],
           let value = AlldayEventsAppereance(rawValue: raw) {
            allDayEvents = value
        }
        if let raw = values[FilterDefaultsKey.noLink],
           let value = NonAlldayEventsAppereance(rawValue: raw) {
            nonAllDayEvents = value
        }
        if let raw = values[FilterDefaultsKey.solo],
           let value = PastEventsAppereance(rawValue: raw) {
            personalEventsAppereance = value
        }
        if let raw = values[FilterDefaultsKey.pending],
           let value = PendingEventsAppereance(rawValue: raw) {
            showPendingEvents = value
        }
        if let raw = values[FilterDefaultsKey.tentative],
           let value = TentativeEventsAppereance(rawValue: raw) {
            showTentativeEvents = value
        }
        if let raw = values[FilterDefaultsKey.declined],
           let value = DeclinedEventsAppereance(rawValue: raw) {
            declinedEventsAppereance = value
        }
        if let raw = values[FilterDefaultsKey.ended],
           let value = PastEventsAppereance(rawValue: raw) {
            pastEventsAppereance = value
        }
        if let raw = values[FilterDefaultsKey.hideFinished] {
            hideFinishedEventsInMenu = (raw == "true")
        }

        MeetingBarLogger.preferences.info(
            "Applied filter preset \(preset.rawValue, privacy: .public)"
        )
    }

    private func revealCustomRows() {
        guard !expandedDisclosures.contains(Self.customDisclosureID) else { return }
        expandedDisclosures.append(Self.customDisclosureID)
    }

    // MARK: - The seven rows

    /// One vocabulary across all seven: **Show / Dim / Hide**. "show as
    /// underlined" and "show with strikethrough" are gone as option words —
    /// three vocabularies collapse into one, and no row is split into a filter
    /// half here and a style half on another pane.
    ///
    /// Two rows name their middle value more precisely because the stored value
    /// genuinely is not "dim": all-day entries can be kept only when they carry
    /// a meeting link, and declined meetings have no plain-show case at all
    /// (`DeclinedEventsAppereance` stores `strikethrough`, which the renderer
    /// draws crossed out). Naming those honestly beats pretending they are Dim.
    private var customSection: some View {
        Section {
            PreferencesDisclosure(
                id: Self.customDisclosureID,
                titleKey: "preferences_filters_custom_title"
            ) {
                Picker("preferences_filters_all_day_title".loco(), selection: $allDayEvents) {
                    Text("preferences_filters_value_show".loco())
                        .tag(AlldayEventsAppereance.show)
                    Text("preferences_filters_value_only_with_link".loco())
                        .tag(AlldayEventsAppereance.show_with_meeting_link_only)
                    Text("preferences_filters_value_hide".loco())
                        .tag(AlldayEventsAppereance.hide)
                }

                Picker("preferences_filters_no_link_title".loco(), selection: $nonAllDayEvents) {
                    Text("preferences_filters_value_show".loco())
                        .tag(NonAlldayEventsAppereance.show)
                    Text("preferences_filters_value_dim".loco())
                        .tag(NonAlldayEventsAppereance.show_inactive_without_meeting_link)
                    Text("preferences_filters_value_hide".loco())
                        .tag(NonAlldayEventsAppereance.hide_without_meeting_link)
                }

                Picker(
                    "preferences_filters_solo_title".loco(),
                    selection: $personalEventsAppereance
                ) {
                    Text("preferences_filters_value_show".loco())
                        .tag(PastEventsAppereance.show_active)
                    Text("preferences_filters_value_dim".loco())
                        .tag(PastEventsAppereance.show_inactive)
                    Text("preferences_filters_value_hide".loco())
                        .tag(PastEventsAppereance.hide)
                }

                Picker("preferences_filters_pending_title".loco(), selection: $showPendingEvents) {
                    Text("preferences_filters_value_show".loco())
                        .tag(PendingEventsAppereance.show)
                    Text("preferences_filters_value_dim".loco())
                        .tag(PendingEventsAppereance.show_inactive)
                    Text("preferences_filters_value_hide".loco())
                        .tag(PendingEventsAppereance.hide)
                }

                Picker(
                    "preferences_filters_tentative_title".loco(),
                    selection: $showTentativeEvents
                ) {
                    Text("preferences_filters_value_show".loco())
                        .tag(TentativeEventsAppereance.show)
                    Text("preferences_filters_value_dim".loco())
                        .tag(TentativeEventsAppereance.show_inactive)
                    Text("preferences_filters_value_hide".loco())
                        .tag(TentativeEventsAppereance.hide)
                }

                Picker(
                    "preferences_filters_declined_title".loco(),
                    selection: $declinedEventsAppereance
                ) {
                    Text("preferences_filters_value_show_crossed_out".loco())
                        .tag(DeclinedEventsAppereance.strikethrough)
                    Text("preferences_filters_value_dim".loco())
                        .tag(DeclinedEventsAppereance.show_inactive)
                    Text("preferences_filters_value_hide".loco())
                        .tag(DeclinedEventsAppereance.hide)
                }

                Picker("preferences_filters_ended_title".loco(), selection: endedVisibility) {
                    Text("preferences_filters_value_show".loco()).tag(FilterVisibility.show)
                    Text("preferences_filters_value_dim".loco()).tag(FilterVisibility.dim)
                    Text("preferences_filters_value_hide".loco()).tag(FilterVisibility.hide)
                }
                helpText("preferences_filters_ended_help")

                // The coupling this pane exists to stop hiding: choosing Dim for
                // pending or tentative invites ALSO removes them from menu-bar
                // next-meeting selection — `PendingEventsAppereance
                // .hidesFromNextEvent` is `.hide || .show_inactive`
                // (EventSelection+MeetingBar.swift), and the same is true of the
                // no-link and solo rows. Behaviour preserved exactly; it is only
                // now stated, because an option whose wording described styling
                // was quietly changing which meeting the menu bar picks.
                helpText("preferences_filters_menu_bar_note")
            }
        }
    }

    /// "Meetings that have ended" is one row over two stored keys, resolved by
    /// the hostless `EndedMeetingsVisibility` (hide wins). They overlapped, could
    /// contradict, and lived on two different tabs with nothing stating
    /// precedence; writing through both keeps them from disagreeing again.
    private var endedVisibility: Binding<FilterVisibility> {
        Binding(
            get: {
                EndedMeetingsVisibility.resolve(
                    pastRawValue: pastEventsAppereance.rawValue,
                    hideFinished: hideFinishedEventsInMenu
                )
            },
            set: { visibility in
                let stored = EndedMeetingsVisibility.storedValues(for: visibility)
                if let past = PastEventsAppereance(rawValue: stored.past) {
                    pastEventsAppereance = past
                }
                hideFinishedEventsInMenu = stored.hideFinished
            }
        )
    }

    // MARK: - The meeting happening now

    /// A filter row like its neighbours: it decides whether a meeting that has
    /// already started still counts as your next one, which is consumed by event
    /// selection and so changes the dropdown's meeting card too — not just the
    /// menu bar, which is why it is not on the Menu Bar pane.
    private var ongoingSection: some View {
        Section {
            Picker(
                "preferences_filters_ongoing_title".loco(),
                selection: $ongoingEventVisibility
            ) {
                Text("preferences_filters_ongoing_until_next".loco())
                    .tag(OngoingEventVisibility.showTenMinBeforeNext)
                Text("preferences_filters_ongoing_ten_minutes".loco())
                    .tag(OngoingEventVisibility.showTenMinAfter)
                Text("preferences_filters_ongoing_never".loco())
                    .tag(OngoingEventVisibility.hideImmediateAfter)
            }
            helpText("preferences_filters_ongoing_help")
        }
    }

    // MARK: - Title patterns

    private var titlePatternSection: some View {
        Section(header: Text("preferences_filters_title_pattern_title".loco())) {
            helpText("preferences_filters_title_pattern_help")

            TextPatternList(patterns: $filterEventRegexes)

            VStack(alignment: .leading, spacing: 6) {
                Text("preferences_filters_title_pattern_test_title".loco())
                    .font(.subheadline)
                TextField(
                    "preferences_filters_title_pattern_test_placeholder".loco(),
                    text: $patternTestTitle
                )
                .textFieldStyle(.roundedBorder)
                if !patternTestTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                    Label(
                        patternTestResultKey.loco(),
                        systemImage: patternTestHidesTitle ? "eye.slash" : "eye"
                    )
                    .font(.caption)
                    .foregroundStyle(patternTestHidesTitle ? Color.orange : Color.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Live, and it runs the shipping filter rather than a second copy of the
    /// rule — a tester that re-implements the rule is a tester that can disagree
    /// with reality.
    private var patternTestHidesTitle: Bool {
        EventFiltering.titleIsFilteredOut(patternTestTitle, patterns: filterEventRegexes)
    }

    private var patternTestResultKey: String {
        patternTestHidesTitle
            ? "preferences_filters_title_pattern_test_hidden"
            : "preferences_filters_title_pattern_test_kept"
    }

    // MARK: - Helpers

    private func helpText(_ key: String) -> some View {
        Text(key.loco())
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "show as underlined" is retired as an option value, so anyone holding it
    /// lands on Dim once — deliberately — instead of meeting a picker with
    /// nothing selected. The stored case still exists and the classic menu still
    /// renders it, so this is a value migration, not a schema change.
    private func retireDeletedOptionValues() {
        if let replacement = FilterVocabularyMigration.migrated(showPendingEvents.rawValue),
           let migrated = PendingEventsAppereance(rawValue: replacement) {
            showPendingEvents = migrated
            MeetingBarLogger.preferences.info("Retired underlined value for showPendingEvents")
        }
        if let replacement = FilterVocabularyMigration.migrated(showTentativeEvents.rawValue),
           let migrated = TentativeEventsAppereance(rawValue: replacement) {
            showTentativeEvents = migrated
            MeetingBarLogger.preferences.info("Retired underlined value for showTentativeEvents")
        }
    }
}

#Preview {
    FiltersTab().frame(width: 700, height: 700)
}
