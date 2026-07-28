//
//  DisplayTab.swift
//  MeetingBarNG
//
//  The dropdown builder sections and the calendar window display section,
//  composed by `DropdownTab` (PreferencesPanes.swift) and `CalendarWindowTab`
//  respectively. The old `DisplayTab` pane struct is gone — the Phase 2 IA
//  restructure split it into the Dropdown and Calendar Window panes.
//
//  DropdownComposerSection was moved here from MenuBuilderTab.swift, originally:
//    Created by Andrii Leitsius on 13.01.2021.
//    Copyright © 2021 Andrii Leitsius. All rights reserved.
//  Licensed under the Apache License, Version 2.0. Modified for MeetingBarNG by
//  Peter Krzyzek / Chykalophia, 2026.
//

import Defaults
import SwiftUI

// MARK: - Composable menu dropdown (MeetingBarNG)

/// Lets the user toggle and reorder the sections shown in the menu dropdown,
/// with a live preview. Mirrors `MenuBarComposerSection`'s UX: ordered rows with
/// up/down/remove buttons and an "Add section" menu. The stored order
/// (`dropdownModuleOrder`) is the full canonical order of every module; the
/// per-module bools drive which are visible. The Preferences footer is pinned
/// (not a module) so the user can never lock themselves out of Settings/Quit.
struct DropdownComposerSection: View {
    @Default(.dropdownModuleOrder) var dropdownModuleOrder
    @Default(.showGreetingInMenu) var showGreetingInMenu
    @Default(.timelineStyle) var timelineStyleRaw
    @Default(.showMeetingControlInMenu) var showMeetingControlInMenu
    @Default(.showAgendaInMenu) var showAgendaInMenu
    @Default(.showJoinSectionInMenu) var showJoinSectionInMenu
    @Default(.showBookmarksInMenu) var showBookmarksInMenu
    @Default(.showCalendarInMenu) var showCalendarInMenu

    // Greeting gear: the name field.
    @Default(.greetingName) var greetingName
    @Default(.greetingShowsDate) var greetingShowsDate
    @Default(.meetingCardShowsProgress) var meetingCardShowsProgress

    // Agenda gear: the per-event-row detail toggles.
    @Default(.shortenEventTitle) var shortenEventTitle
    @Default(.menuEventTitleLength) var menuEventTitleLength
    @Default(.showEventEndTime) var showEventEndTime
    @Default(.showMeetingServiceIcon) var showMeetingServiceIcon
    @Default(.showEventCalendarColor) var showEventCalendarColor
    @Default(.showMeetingPrepLinks) var showMeetingPrepLinks

    // Which module's gear popover is open.
    @State private var gearOpenModule: DropdownModule?

    /// The full canonical order of every module: the stored order parsed +
    /// de-duped, with any missing module reappended in standard position.
    private var fullOrder: [DropdownModule] {
        var seen = Set<DropdownModule>()
        var ordered: [DropdownModule] = []
        for raw in dropdownModuleOrder {
            guard let module = DropdownModule(rawValue: raw), seen.insert(module).inserted else {
                continue
            }
            ordered.append(module)
        }
        for module in DropdownComposition.standard.modules where seen.insert(module).inserted {
            ordered.append(module)
        }
        return ordered
    }

    /// The visible (enabled) modules, in order — the same resolution the status
    /// bar controller uses, so the preview matches the real dropdown.
    private var visibleModules: [DropdownModule] {
        DropdownCompositionPolicy.resolve(order: dropdownModuleOrder, enabled: enabledRawValues)
    }

    private var enabledRawValues: Set<String> {
        DropdownCompositionPolicy.enabledRawValues(
            greeting: showGreetingInMenu,
            // The style picker owns the timeline's visibility.
            timeline: (TimelineStyle(rawValue: timelineStyleRaw) ?? .relative).isVisible,
            meeting: showMeetingControlInMenu,
            agenda: showAgendaInMenu,
            join: showJoinSectionInMenu,
            bookmarks: showBookmarksInMenu,
            calendar: showCalendarInMenu
        )
    }

    /// Modules currently hidden — offered in the "Add section" menu, in standard order.
    private var hiddenModules: [DropdownModule] {
        DropdownComposition.standard.modules.filter { !isEnabled($0) }
    }

    var body: some View {
        Section(header: Text("preferences_dropdown_blocks_title".loco())) {
            Text("preferences_dropdown_blocks_help".loco())
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Section {
            ForEach(Array(visibleModules.enumerated()), id: \.element) { pair in
                moduleRow(module: pair.element, index: pair.offset)
            }
            if !hiddenModules.isEmpty {
                Menu {
                    ForEach(hiddenModules, id: \.self) { module in
                        Button {
                            setEnabled(module, true)
                        } label: {
                            Label(moduleName(module), systemImage: moduleSymbol(module))
                        }
                    }
                } label: {
                    Label(
                        "preferences_dropdown_block_add".loco(),
                        systemImage: "plus"
                    )
                }
            }
        }

        // No preview section here: the live preview pane beside this form already
        // draws the real dropdown from this same resolved module list, including
        // the pinned Preferences footer. A second, text-only preview inside the
        // form was the "two previews" duplication.
    }

    // MARK: Rows

    private func moduleRow(module: DropdownModule, index: Int) -> some View {
        HStack {
            Label(moduleName(module), systemImage: moduleSymbol(module))
            Spacer()

            if hasGear(module) {
                Button {
                    gearOpenModule = (gearOpenModule == module) ? nil : module
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("preferences_menubar_block_configure".loco())
                .popover(isPresented: gearBinding(for: module)) {
                    moduleGearContent(module)
                        .frame(width: 320)
                        .padding(16)
                }
            }

            Button { move(from: index, by: -1) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .help("preferences_menubar_block_move_up".loco())

            Button { move(from: index, by: 1) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == visibleModules.count - 1)
            .help("preferences_menubar_block_move_down".loco())

            Button { setEnabled(module, false) } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("preferences_dropdown_block_remove".loco())
        }
    }

    /// Modules that have configurable options get a gear; others are just
    /// show/hide with nothing to configure.
    private func hasGear(_ module: DropdownModule) -> Bool {
        switch module {
        case .greeting, .agenda, .meeting: return true
        case .timeline, .join, .bookmarks, .calendar: return false
        }
    }

    private func gearBinding(for module: DropdownModule) -> Binding<Bool> {
        Binding(
            get: { gearOpenModule == module },
            set: { isOn in gearOpenModule = isOn ? module : nil }
        )
    }

    /// The popover content for a module's gear.
    @ViewBuilder
    private func moduleGearContent(_ module: DropdownModule) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(moduleName(module))
                .font(.headline)
                .foregroundStyle(.primary)

            switch module {
            case .greeting:
                TextField(
                    preferenceLabel("preferences_dropdown_greeting_name_title"),
                    text: $greetingName,
                    prompt: Text("preferences_dropdown_greeting_name_placeholder".loco())
                )
                helpText("preferences_dropdown_greeting_name_help")
                Divider()
                Toggle(
                    preferenceLabel("preferences_dropdown_greeting_date_toggle"),
                    isOn: $greetingShowsDate
                )
                helpText("preferences_dropdown_greeting_date_help")

            case .meeting:
                Toggle(
                    preferenceLabel("preferences_dropdown_meeting_progress_toggle"),
                    isOn: $meetingCardShowsProgress
                )
                helpText("preferences_dropdown_meeting_progress_help")

            case .agenda:
                Toggle(
                    preferenceLabel("preferences_dropdown_rows_end_time_toggle"),
                    isOn: $showEventEndTime
                )
                Toggle(
                    preferenceLabel("preferences_dropdown_rows_service_icon_toggle"),
                    isOn: $showMeetingServiceIcon
                )
                Toggle(
                    preferenceLabel("preferences_dropdown_rows_calendar_color_toggle"),
                    isOn: $showEventCalendarColor
                )
                Toggle(
                    preferenceLabel("preferences_dropdown_rows_prep_links_toggle"),
                    isOn: $showMeetingPrepLinks
                )
                Divider()
                Toggle(
                    preferenceLabel("preferences_dropdown_rows_shorten_toggle"),
                    isOn: $shortenEventTitle
                )
                PresetNumberPicker(
                    presets: [20, 30, 50, 80],
                    presetLabel: { "\($0)" },
                    customLabel: "preferences_preset_custom".loco(),
                    value: $menuEventTitleLength,
                    range: 20 ... 100,
                    step: 5,
                    stepperLabel: { "preferences_dropdown_rows_shorten_stepper".loco($0) },
                    example: "preferences_dropdown_rows_shorten_example".loco(),
                    isEnabled: shortenEventTitle
                )

            case .timeline, .join, .bookmarks, .calendar:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func helpText(_ key: String) -> some View {
        PreferencesHelpText(key: key)
    }

    // MARK: Data

    private func moduleName(_ module: DropdownModule) -> String {
        switch module {
        case .greeting: return "preferences_dropdown_block_greeting".loco()
        case .timeline: return "preferences_dropdown_block_timeline".loco()
        case .meeting: return "preferences_dropdown_block_meeting".loco()
        case .agenda: return "preferences_dropdown_block_agenda".loco()
        case .join: return "preferences_dropdown_block_join".loco()
        case .bookmarks: return "preferences_dropdown_block_bookmarks".loco()
        case .calendar: return "preferences_dropdown_block_calendar".loco()
        }
    }

    private func moduleSymbol(_ module: DropdownModule) -> String {
        switch module {
        case .greeting: return "hand.wave"
        case .timeline: return "chart.bar.xaxis"
        case .meeting: return "video"
        case .agenda: return "calendar"
        case .join: return "arrow.up.right.square"
        case .bookmarks: return "bookmark"
        case .calendar: return "calendar"
        }
    }

    private func isEnabled(_ module: DropdownModule) -> Bool {
        switch module {
        case .greeting: return showGreetingInMenu
        case .timeline: return (TimelineStyle(rawValue: timelineStyleRaw) ?? .relative).isVisible
        case .meeting: return showMeetingControlInMenu
        case .agenda: return showAgendaInMenu
        case .join: return showJoinSectionInMenu
        case .bookmarks: return showBookmarksInMenu
        case .calendar: return showCalendarInMenu
        }
    }

    // MARK: Mutation

    private func setEnabled(_ module: DropdownModule, _ value: Bool) {
        switch module {
        case .greeting: showGreetingInMenu = value
        // Hiding the timeline from the composer means choosing the `off`
        // style; showing it restores the previous one.
        case .timeline: timelineStyleRaw = value ? TimelineStyle.relative.rawValue : TimelineStyle.off.rawValue
        case .meeting: showMeetingControlInMenu = value
        case .agenda: showAgendaInMenu = value
        case .join: showJoinSectionInMenu = value
        case .bookmarks: showBookmarksInMenu = value
        case .calendar: showCalendarInMenu = value
        }
    }

    /// Reorders the visible module at display `index` by `offset`, then rewrites
    /// the stored full order so hidden modules keep their existing slots.
    private func move(from index: Int, by offset: Int) {
        var visible = visibleModules
        let target = index + offset
        guard visible.indices.contains(index), visible.indices.contains(target) else { return }
        visible.swapAt(index, target)

        // Rebuild the full order: fill each enabled slot from the new visible
        // sequence, leaving disabled modules exactly where they were.
        var iterator = visible.makeIterator()
        let rebuilt = fullOrder.map { module -> DropdownModule in
            isEnabled(module) ? (iterator.next() ?? module) : module
        }
        dropdownModuleOrder = rebuilt.map(\.rawValue)
    }
}

// MARK: - Dropdown display

/// Dropdown settings that are NOT plain on/off duplicates of a composer module:
/// the Reminders toggles. The greeting NAME field moved into the greeting
/// block's gear popover. Reminders is not a composer module, so its on/off
/// toggle stays here. It requests Reminders access as a side effect, as does the
/// permission toggle on the Calendars pane — two entry points, one system
/// permission; neither is exclusive.
struct DropdownDisplaySection: View {
    @Default(.showRemindersInMenu) var showRemindersInMenu
    @Default(.remindersIncludeOverdue) var remindersIncludeOverdue
    @Default(.eventActionHighlightMinutes) var eventActionHighlightMinutes
    @Default(.dropdownMaxEventRows) var dropdownMaxEventRows
    @Default(.dropdownDensity) var dropdownDensityRaw
    @Default(.timelineStyle) var timelineStyleRaw

    /// Bridges the raw-string Default to the hostless enum. An unrecognised
    /// stored value reads back as `.standard` rather than leaving the picker
    /// with no selection.
    private var densityBinding: Binding<DropdownDensity> {
        Binding(
            get: { DropdownDensity(rawValue: dropdownDensityRaw) ?? .standard },
            set: { dropdownDensityRaw = $0.rawValue }
        )
    }

    private var timelineStyleBinding: Binding<TimelineStyle> {
        Binding(
            get: { TimelineStyle(rawValue: timelineStyleRaw) ?? .relative },
            set: { timelineStyleRaw = $0.rawValue }
        )
    }

    var body: some View {
        Section {
            Picker(
                "preferences_dropdown_timeline_style_title".loco(),
                selection: timelineStyleBinding
            ) {
                Text("preferences_dropdown_timeline_style_relative".loco())
                    .tag(TimelineStyle.relative)
                Text("preferences_dropdown_timeline_style_day".loco())
                    .tag(TimelineStyle.day)
            }
            .pickerStyle(.segmented)
            .annotation("preferences_dropdown_timeline_style_help")

            Picker(
                "preferences_dropdown_density_title".loco(),
                selection: densityBinding
            ) {
                Text("preferences_dropdown_density_compact".loco()).tag(DropdownDensity.compact)
                Text("preferences_dropdown_density_standard".loco()).tag(DropdownDensity.standard)
                Text("preferences_dropdown_density_roomy".loco()).tag(DropdownDensity.roomy)
            }
            .pickerStyle(.segmented)
            .annotation("preferences_dropdown_density_help")

            Text("preferences_dropdown_max_rows_title".loco())
            PresetNumberPicker(
                presets: [5, 10, 15, 0],
                // 0 is the "off" value, and "0 meetings" would read as "hide them
                // all" — the one preset whose number has to be spelled out.
                presetLabel: { $0 == 0 ? "preferences_dropdown_max_rows_unlimited".loco() : "\($0)" },
                customLabel: "preferences_preset_custom".loco(),
                value: $dropdownMaxEventRows,
                range: 0 ... 100,
                step: 1,
                stepperLabel: { "preferences_dropdown_max_rows_stepper".loco($0) },
                example: "preferences_dropdown_max_rows_example".loco(),
                isEnabled: true
            )
            Text("preferences_dropdown_action_highlight_title".loco())
            PresetNumberPicker(
                presets: [0, 2, 5, 15],
                // 0 is not "no lead time" to a reader, it is "when it starts" —
                // the one preset whose number needs spelling out.
                presetLabel: { $0 == 0 ? "preferences_dropdown_action_highlight_now".loco() : "\($0)" },
                customLabel: "preferences_preset_custom".loco(),
                value: $eventActionHighlightMinutes,
                range: 0 ... 120,
                step: 1,
                stepperLabel: { "preferences_dropdown_action_highlight_stepper".loco($0) },
                example: "preferences_dropdown_action_highlight_example".loco(),
                isEnabled: true
            )
            // Reminders (Dot parity). Turning this on requests Reminders access
            // and only flips on if granted. NOT the only such gate — the
            // permission toggle on the Calendars pane requests the same access
            // independently; both drive one system permission.
            Toggle(
                preferenceLabel("preferences_dropdown_reminders_toggle"),
                isOn: showRemindersBinding
            )
            Toggle(
                preferenceLabel("preferences_dropdown_reminders_overdue_toggle"),
                isOn: $remindersIncludeOverdue
            )
            .preferenceIndent()
            .disabled(!showRemindersInMenu)
        }
    }

    /// Enabling the feature first requests Reminders access; the setting only
    /// flips on when access is granted, so a denied prompt leaves the toggle off.
    private var showRemindersBinding: Binding<Bool> {
        Binding(
            get: { showRemindersInMenu },
            set: { isOn in
                if isOn {
                    Task {
                        let granted = await RemindersStore.shared.requestAccess()
                        await MainActor.run { showRemindersInMenu = granted }
                    }
                } else {
                    showRemindersInMenu = false
                }
            }
        )
    }
}

// MARK: - Calendar window display

/// Display options for the standalone calendar window (the month/week grid),
/// kept separate from the dropdown options above because they affect a different
/// surface. The window's own Month/Week fold lives in its header; the stored
/// default, weekend dimming, first weekday, week numbers, and per-day event cap
/// are persistent preferences.
struct CalendarWindowDisplaySection: View {
    @Default(.dimWeekendsInCalendar) var dimWeekendsInCalendar
    @Default(.calendarGridMode) var calendarGridMode
    @Default(.calendarFirstWeekday) var calendarFirstWeekday
    @Default(.showWeekNumbersInCalendar) var showWeekNumbersInCalendar
    @Default(.maxEventsPerCalendarDay) var maxEventsPerCalendarDay

    var body: some View {
        Section {
            Toggle(
                preferenceLabel("preferences_calendarwindow_dim_weekends_toggle"),
                isOn: $dimWeekendsInCalendar
            )
            Text("preferences_calendarwindow_dim_weekends_help".loco())
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Section {
            Picker(
                "preferences_calendarwindow_open_in_title".loco(),
                selection: gridModeBinding
            ) {
                Text("calendar_grid_mode_month".loco()).tag(CalendarGridMode.month)
                Text("calendar_grid_mode_week".loco()).tag(CalendarGridMode.week)
            }
            Text("preferences_calendarwindow_open_in_help".loco())
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Section {
            Picker(
                "preferences_calendarwindow_first_weekday_title".loco(),
                selection: $calendarFirstWeekday
            ) {
                Text("preferences_calendarwindow_first_weekday_auto".loco()).tag(0)
                Text("preferences_calendarwindow_first_weekday_sunday".loco()).tag(1)
                Text("preferences_calendarwindow_first_weekday_monday".loco()).tag(2)
            }
            Text("preferences_calendarwindow_first_weekday_help".loco())
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Section {
            Toggle(
                preferenceLabel("preferences_calendarwindow_week_numbers_toggle"),
                isOn: $showWeekNumbersInCalendar
            )
            Text("preferences_calendarwindow_week_numbers_help".loco())
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Section {
            Picker(
                "preferences_calendarwindow_event_cap_title".loco(),
                selection: $maxEventsPerCalendarDay
            ) {
                Text("1").tag(1)
                Text("2").tag(2)
                Text("3").tag(3)
                Text("4").tag(4)
                Text("5").tag(5)
            }
            Text("preferences_calendarwindow_event_cap_help".loco())
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var gridModeBinding: Binding<CalendarGridMode> {
        Binding(
            get: { CalendarGridMode(rawValue: calendarGridMode) ?? .month },
            set: { calendarGridMode = $0.rawValue }
        )
    }
}

#Preview {
    PreferencesGroupedForm {
        DropdownComposerSection()
        DropdownDisplaySection()
        CalendarWindowDisplaySection()
    }
    .frame(width: 560, height: 620)
}
