//
//  DisplayTab.swift
//  MeetingBarNG
//
//  The "Display" preferences tab: how MeetingBarNG presents itself in the menu
//  bar and its dropdown. Phase 1 of the Preferences IA overhaul merges the
//  former menu-bar appearance tab (StatusBarSection) with the composable
//  menu-bar / dropdown builders and the dropdown display toggles.
//
//  StatusBarSection and MenuBarComposerSection were moved here from
//  AppearanceTab.swift; DropdownComposerSection was moved here from
//  MenuBuilderTab.swift, originally:
//    Created by Andrii Leitsius on 13.01.2021.
//    Copyright © 2021 Andrii Leitsius. All rights reserved.
//  Licensed under the Apache License, Version 2.0. Modified for MeetingBarNG by
//  Peter Krzyzek / Chykalophia, 2026: relocated into the Display tab and split
//  the dropdown display toggles into `DropdownDisplaySection` (Phase 1); wrap the
//  settings sections in a two-pane layout with a sticky `DisplayPreviewPane` live
//  preview on the right (Phase 2); Phase 3 legibility pass — plain-language
//  labels, `PresetNumberPicker` chips for the menu-bar title length and the
//  look-ahead threshold, and dropped the greeting/timeline on/off toggles from
//  `DropdownDisplaySection` (the composer's module list is now their single
//  source of truth); added `CalendarWindowDisplaySection` for the calendar
//  window's dim-weekends preference; added the `useSwiftUIDropdown` switch to
//  `DropdownDisplaySection` — the SwiftUI panel is now the DEFAULT dropdown and
//  the switch is the escape hatch back to the classic NSMenu, not an opt-in.
//

import Defaults
import SwiftUI

struct DisplayTab: View {
    var body: some View {
        // Two-pane: the settings sections scroll on the left; a fixed-width live
        // preview stays pinned on the right. Only the Display tab gets a preview.
        HStack(spacing: 0) {
            PreferencesGroupedForm {
                // "Menu bar" — the classic status-bar icon/title/time controls.
                StatusBarSection()
                // "Menu bar layout" — composable menu-bar token builder.
                MenuBarComposerSection()
                // "Dropdown layout" — composable dropdown section builder.
                DropdownComposerSection()
                // "Dropdown" — dropdown display toggles (timeline, greeting, …).
                DropdownDisplaySection()
                // "Calendar window" — the month/week grid window's display options.
                CalendarWindowDisplaySection()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            DisplayPreviewPane()
                .frame(width: 340)
                .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Status bar (menu bar)

struct StatusBarSection: View {
    @Default(.eventTitleIconFormat) var eventTitleIconFormat
    @Default(.eventTitleFormat) var eventTitleFormat
    @Default(.eventTimeFormat) var eventTimeFormat
    @Default(.statusbarEventTitleLength) var statusbarEventTitleLength
    @Default(.showEventMaxTimeUntilEventThreshold) var showEventMaxTimeUntilEventThreshold
    @Default(.showEventMaxTimeUntilEventEnabled) var showEventMaxTimeUntilEventEnabled
    @Default(.ongoingEventVisibility) var ongoingEventVisibility

    var body: some View {
        Section(header: Text("preferences_appearance_status_bar_title".loco())) {
            Picker(
                preferenceLabel("preferences_appearance_status_bar_icon_title"),
                selection: $eventTitleIconFormat
            ) {
                HStack {
                    Image(nsImage: getImage(iconName: EventTitleIconFormat.calendar.rawValue))
                        .resizable()
                        .frame(width: 16.0, height: 16.0)
                    Text("preferences_appearance_status_bar_icon_calendar_icon_value".loco())
                }.tag(EventTitleIconFormat.calendar)

                HStack {
                    Image(nsImage: getImage(iconName: EventTitleIconFormat.appicon.rawValue))
                        .resizable()
                        .frame(width: 16.0, height: 16.0)
                    Text("preferences_appearance_status_bar_icon_app_icon_value".loco())
                }.tag(EventTitleIconFormat.appicon)

                HStack {
                    Image(nsImage: getImage(iconName: EventTitleIconFormat.eventtype.rawValue))
                        .resizable()
                        .frame(width: 16.0, height: 16.0)
                    Text("preferences_appearance_status_bar_icon_specific_icon_value".loco())
                }.tag(EventTitleIconFormat.eventtype)

                HStack {
                    Image(nsImage: getImage(iconName: EventTitleIconFormat.none.rawValue))
                        .resizable()
                        .frame(width: 16.0, height: 16.0)
                    Text("preferences_appearance_status_bar_icon_no_icon_value".loco())
                }.tag(EventTitleIconFormat.none)
            }

            if eventTitleIconFormat == .none {
                Text("preferences_appearance_status_bar_icon_none_help".loco())
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker(
                preferenceLabel("preferences_appearance_status_bar_title_title"),
                selection: $eventTitleFormat
            ) {
                Text("preferences_appearance_status_bar_title_event_title_value".loco())
                    .tag(EventTitleFormat.show)
                Text("preferences_appearance_status_bar_title_generic_value".loco())
                    .tag(EventTitleFormat.generic)
                Text("preferences_appearance_status_bar_title_dot_value".loco())
                    .tag(EventTitleFormat.dot)
                Text("preferences_appearance_status_bar_title_hide_value".loco())
                    .tag(EventTitleFormat.none)
            }

            PresetNumberPicker(
                presets: [20, 30, 50, 80],
                presetLabel: { "\($0)" },
                customLabel: "preferences_preset_custom".loco(),
                value: $statusbarEventTitleLength,
                range: statusbarEventTitleLengthLimits.min ... statusbarEventTitleLengthLimits.max,
                step: 5,
                stepperLabel: { "preferences_appearance_status_bar_title_shorten_stepper".loco($0) },
                example: "preferences_appearance_status_bar_title_shorten_example".loco(),
                isEnabled: eventTitleFormat == .show
            )

            Picker(
                preferenceLabel("preferences_appearance_status_bar_time_title"),
                selection: $eventTimeFormat
            ) {
                ForEach(PreferencesStatusBarTimeOption.allCases, id: \.format) { option in
                    Text(option.titleKey.loco()).tag(option.format)
                }
            }
        }

        Section {
            Toggle(
                preferenceLabel("preferences_appearance_status_bar_next_event_toggle"),
                isOn: $showEventMaxTimeUntilEventEnabled
            )

            PresetNumberPicker(
                presets: [15, 30, 60, 120, 240],
                presetLabel: minutesPresetLabel,
                customLabel: "preferences_preset_custom".loco(),
                value: $showEventMaxTimeUntilEventThreshold,
                range: 5 ... 720,
                step: 5,
                stepperLabel: { "preferences_appearance_status_bar_next_event_stepper".loco($0) },
                example: "preferences_appearance_status_bar_next_event_example".loco(),
                isEnabled: showEventMaxTimeUntilEventEnabled
            )

            Picker(
                preferenceLabel("preferences_appearance_status_bar_ongoing_title"),
                selection: $ongoingEventVisibility
            ) {
                Text("preferences_appearance_status_bar_ongoing_time_immediate_value".loco())
                    .tag(OngoingEventVisibility.hideImmediateAfter)
                Text("preferences_appearance_status_bar_ongoing_time_ten_after_value".loco())
                    .tag(OngoingEventVisibility.showTenMinAfter)
                Text("preferences_appearance_status_bar_ongoing_time_ten_before_next_value".loco())
                    .tag(OngoingEventVisibility.showTenMinBeforeNext)
            }
        }
    }

    func getImage(iconName: String) -> NSImage {
        let icon = NSImage(named: iconName)
        icon!.size = NSSize(width: 16, height: 16)
        return icon!
    }

    /// Renders a look-ahead preset as a short duration chip: "15m", "1h", "2h".
    func minutesPresetLabel(_ minutes: Int) -> String {
        minutes < 60
            ? "preferences_preset_minutes_short".loco(minutes)
            : "preferences_preset_hours_short".loco(minutes / 60)
    }
}

// MARK: - Composable menu bar (MeetingBarNG)

/// Lets the user compose the menu-bar title from ordered tokens. When no tokens
/// are set, the classic `StatusBarSection` settings drive the menu bar, so
/// existing installs are unaffected until the user opts in here.
struct MenuBarComposerSection: View {
    @Default(.menuBarTokens) var menuBarTokens
    @Default(.menuBarCountdownStyle) var menuBarCountdownStyle
    @Default(.menuBarDateStyle) var menuBarDateStyle
    @Default(.menuBarProgressStyle) var menuBarProgressStyle
    @Default(.menuBarWorldClockTimeZone) var menuBarWorldClockTimeZone
    @Default(.menuBarWorldClockLabel) var menuBarWorldClockLabel

    // Sticky "Custom" override: the token editor stays revealed once the user
    // picks Custom, even if their current tokens happen to match a named preset.
    // (`MenuBarPreset.detect` alone would otherwise snap the picker back.)
    @State private var forceCustom = false

    private var tokens: [MenuBarTokenKind] {
        var seen = Set<MenuBarTokenKind>()
        return menuBarTokens
            .compactMap(MenuBarTokenKind.init(rawValue:))
            .filter { seen.insert($0).inserted }
    }

    private var isEnabled: Bool { !tokens.isEmpty }

    private var availableTokens: [MenuBarTokenKind] {
        MenuBarTokenKind.allCases.filter { !tokens.contains($0) }
    }

    /// The layout preset currently reflected by the picker. A named preset is
    /// derived from the live tokens; `.custom` is shown once the user forces it
    /// (see `forceCustom`) so the manual token editor stays revealed.
    private var selectedPreset: MenuBarPreset {
        forceCustom ? .custom : MenuBarPreset.detect(tokens: tokens)
    }

    var body: some View {
        Section(header: Text("preferences_appearance_menu_bar_composer_title".loco())) {
            Toggle(
                preferenceLabel("preferences_appearance_menu_bar_composer_enable_toggle"),
                isOn: enabledBinding
            )
            Text("preferences_appearance_menu_bar_composer_hint".loco())
                .font(.caption)
                .foregroundColor(.secondary)
        }

        if isEnabled {
            Section {
                Picker(
                    preferenceLabel("preferences_menu_bar_preset_title"),
                    selection: presetBinding
                ) {
                    Text("preferences_menu_bar_preset_classic".loco()).tag(MenuBarPreset.classic)
                    Text("preferences_menu_bar_preset_minimal".loco()).tag(MenuBarPreset.minimal)
                    Text("preferences_menu_bar_preset_agenda".loco()).tag(MenuBarPreset.agenda)
                    Text("preferences_menu_bar_preset_info".loco()).tag(MenuBarPreset.info)
                    Text("preferences_menu_bar_preset_custom".loco()).tag(MenuBarPreset.custom)
                }
                .pickerStyle(.segmented)
            }

            // The manual token editor is shown only for the "Custom" preset; the
            // named presets are kept simple (preview + preset chips are enough).
            if selectedPreset == .custom {
                Section {
                    ForEach(Array(tokens.enumerated()), id: \.element) { pair in
                        tokenRow(token: pair.element, index: pair.offset)
                    }
                    if !availableTokens.isEmpty {
                        Menu {
                            ForEach(availableTokens, id: \.self) { token in
                                Button(tokenName(token)) { add(token) }
                            }
                        } label: {
                            Label(
                                "preferences_appearance_menu_bar_composer_add".loco(),
                                systemImage: "plus"
                            )
                        }
                    }
                }
            }

            if tokens.contains(.countdown) {
                Section {
                    Picker(
                        preferenceLabel("preferences_appearance_menu_bar_countdown_style_title"),
                        selection: countdownStyleBinding
                    ) {
                        Text("preferences_appearance_menu_bar_countdown_style_compact_value".loco())
                            .tag(CountdownStyle.compact)
                        Text("preferences_appearance_menu_bar_countdown_style_full_value".loco())
                            .tag(CountdownStyle.full)
                        Text("preferences_appearance_menu_bar_countdown_style_digital_value".loco())
                            .tag(CountdownStyle.digital)
                    }
                }
            }

            if tokens.contains(.date) {
                Section {
                    Picker(
                        preferenceLabel("preferences_appearance_menu_bar_date_style_title"),
                        selection: dateStyleBinding
                    ) {
                        Text("preferences_appearance_menu_bar_date_style_weekday_value".loco())
                            .tag(MenuBarDateStyle.weekday)
                        Text("preferences_appearance_menu_bar_date_style_medium_value".loco())
                            .tag(MenuBarDateStyle.medium)
                        Text("preferences_appearance_menu_bar_date_style_short_value".loco())
                            .tag(MenuBarDateStyle.short)
                    }
                }
            }

            if tokens.contains(.progress) {
                Section {
                    Picker(
                        preferenceLabel("preferences_appearance_menu_bar_progress_style_title"),
                        selection: progressStyleBinding
                    ) {
                        Text("preferences_appearance_menu_bar_progress_style_day_value".loco())
                            .tag(MenuBarProgressStyle.day)
                        Text("preferences_appearance_menu_bar_progress_style_year_value".loco())
                            .tag(MenuBarProgressStyle.year)
                    }
                }
            }

            if tokens.contains(.worldClock) {
                Section {
                    Picker(
                        preferenceLabel("preferences_appearance_menu_bar_world_clock_timezone_title"),
                        selection: $menuBarWorldClockTimeZone
                    ) {
                        ForEach(TimeZone.knownTimeZoneIdentifiers.sorted(), id: \.self) { identifier in
                            Text(identifier).tag(identifier)
                        }
                    }
                    TextField(
                        preferenceLabel("preferences_appearance_menu_bar_world_clock_label_title"),
                        text: $menuBarWorldClockLabel,
                        prompt: Text("preferences_appearance_menu_bar_world_clock_label_placeholder".loco())
                    )
                }
            }

            // No preview section here: the live preview pane beside this form
            // already renders the composed menu-bar strip from the same tokens.
            // A second, lesser preview inside the form was pure duplication.
        }
    }

    // MARK: Rows

    private func tokenRow(token: MenuBarTokenKind, index: Int) -> some View {
        HStack {
            Text(tokenName(token))
            Spacer()
            Button { move(from: index, by: -1) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .help("preferences_appearance_menu_bar_composer_move_up".loco())

            Button { move(from: index, by: 1) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == tokens.count - 1)
            .help("preferences_appearance_menu_bar_composer_move_down".loco())

            Button { remove(token) } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("preferences_appearance_menu_bar_composer_remove".loco())
        }
    }

    // MARK: Data

    private func tokenName(_ token: MenuBarTokenKind) -> String {
        switch token {
        case .icon: return "preferences_appearance_menu_bar_token_icon".loco()
        case .title: return "preferences_appearance_menu_bar_token_title".loco()
        case .countdown: return "preferences_appearance_menu_bar_token_countdown".loco()
        case .date: return "preferences_appearance_menu_bar_token_date".loco()
        case .clock: return "preferences_appearance_menu_bar_token_clock".loco()
        case .progress: return "preferences_appearance_menu_bar_token_progress".loco()
        case .weekNumber: return "preferences_appearance_menu_bar_token_week_number".loco()
        case .worldClock: return "preferences_appearance_menu_bar_token_world_clock".loco()
        }
    }

    // MARK: Mutation

    private func write(_ newTokens: [MenuBarTokenKind]) {
        menuBarTokens = newTokens.map(\.rawValue)
    }

    private func move(from index: Int, by offset: Int) {
        var updated = tokens
        let target = index + offset
        guard updated.indices.contains(index), updated.indices.contains(target) else { return }
        updated.swapAt(index, target)
        write(updated)
    }

    private func remove(_ token: MenuBarTokenKind) {
        write(tokens.filter { $0 != token })
    }

    private func add(_ token: MenuBarTokenKind) {
        guard !tokens.contains(token) else { return }
        write(tokens + [token])
    }

    // MARK: Bindings

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { isOn in
                if isOn {
                    if tokens.isEmpty { write(MenuBarComposition.derivedFromLegacy.tokens) }
                } else {
                    forceCustom = false
                    menuBarTokens = []
                }
            }
        )
    }

    /// Layout-preset picker binding. Selecting a named preset writes its token
    /// list (which also keeps the composable path active, since the list is
    /// non-empty). Selecting "Custom" writes nothing — it reveals the token
    /// editor seeded from the current tokens.
    private var presetBinding: Binding<MenuBarPreset> {
        Binding(
            get: { selectedPreset },
            set: { preset in
                if preset == .custom {
                    forceCustom = true
                } else {
                    forceCustom = false
                    write(preset.tokens)
                }
            }
        )
    }

    private var countdownStyleBinding: Binding<CountdownStyle> {
        Binding(
            get: { CountdownStyle(rawValue: menuBarCountdownStyle) ?? .full },
            set: { menuBarCountdownStyle = $0.rawValue }
        )
    }

    private var dateStyleBinding: Binding<MenuBarDateStyle> {
        Binding(
            get: { MenuBarDateStyle(rawValue: menuBarDateStyle) ?? .medium },
            set: { menuBarDateStyle = $0.rawValue }
        )
    }

    private var progressStyleBinding: Binding<MenuBarProgressStyle> {
        Binding(
            get: { MenuBarProgressStyle(rawValue: menuBarProgressStyle) ?? .day },
            set: { menuBarProgressStyle = $0.rawValue }
        )
    }
}

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
    @Default(.showTimelineInMenu) var showTimelineInMenu
    @Default(.showMeetingControlInMenu) var showMeetingControlInMenu
    @Default(.showAgendaInMenu) var showAgendaInMenu
    @Default(.showJoinSectionInMenu) var showJoinSectionInMenu
    @Default(.showBookmarksInMenu) var showBookmarksInMenu

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
            timeline: showTimelineInMenu,
            meeting: showMeetingControlInMenu,
            agenda: showAgendaInMenu,
            join: showJoinSectionInMenu,
            bookmarks: showBookmarksInMenu
        )
    }

    /// Modules currently hidden — offered in the "Add section" menu, in standard order.
    private var hiddenModules: [DropdownModule] {
        DropdownComposition.standard.modules.filter { !isEnabled($0) }
    }

    var body: some View {
        Section(header: Text("preferences_menu_builder_dropdown_title".loco())) {
            Text("preferences_menu_builder_dropdown_hint".loco())
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
                        "preferences_menu_builder_dropdown_add".loco(),
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
            Button { move(from: index, by: -1) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .help("preferences_appearance_menu_bar_composer_move_up".loco())

            Button { move(from: index, by: 1) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == visibleModules.count - 1)
            .help("preferences_appearance_menu_bar_composer_move_down".loco())

            Button { setEnabled(module, false) } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("preferences_appearance_menu_bar_composer_remove".loco())
        }
    }

    // MARK: Data

    private func moduleName(_ module: DropdownModule) -> String {
        switch module {
        case .greeting: return "preferences_menu_builder_dropdown_module_greeting".loco()
        case .timeline: return "preferences_menu_builder_dropdown_module_timeline".loco()
        case .meeting: return "preferences_menu_builder_dropdown_module_meeting".loco()
        case .agenda: return "preferences_menu_builder_dropdown_module_agenda".loco()
        case .join: return "preferences_menu_builder_dropdown_module_join".loco()
        case .bookmarks: return "preferences_menu_builder_dropdown_module_bookmarks".loco()
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
        }
    }

    private func isEnabled(_ module: DropdownModule) -> Bool {
        switch module {
        case .greeting: return showGreetingInMenu
        case .timeline: return showTimelineInMenu
        case .meeting: return showMeetingControlInMenu
        case .agenda: return showAgendaInMenu
        case .join: return showJoinSectionInMenu
        case .bookmarks: return showBookmarksInMenu
        }
    }

    // MARK: Mutation

    private func setEnabled(_ module: DropdownModule, _ value: Bool) {
        switch module {
        case .greeting: showGreetingInMenu = value
        case .timeline: showTimelineInMenu = value
        case .meeting: showMeetingControlInMenu = value
        case .agenda: showAgendaInMenu = value
        case .join: showJoinSectionInMenu = value
        case .bookmarks: showBookmarksInMenu = value
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
/// hide-finished, the greeting NAME field, and the Reminders toggles. The
/// greeting and timeline *visibility* toggles were dropped here in Phase 3 —
/// `DropdownComposerSection`'s module list is now their single source of truth,
/// so they are no longer rendered twice. Reminders is not a composer module, so
/// its on/off toggle stays here (it is also the only place that requests
/// Reminders access).
struct DropdownDisplaySection: View {
    @Default(.hideFinishedEventsInMenu) var hideFinishedEventsInMenu
    @Default(.useSwiftUIDropdown) var useSwiftUIDropdown
    // Read-only here: the greeting section is shown/hidden in "Dropdown layout"
    // above; this key only gates whether the greeting NAME field is editable.
    @Default(.showGreetingInMenu) var showGreetingInMenu
    @Default(.greetingName) var greetingName
    @Default(.showRemindersInMenu) var showRemindersInMenu
    @Default(.remindersIncludeOverdue) var remindersIncludeOverdue

    var body: some View {
        Section(header: Text("preferences_appearance_menu_title".loco())) {
            Toggle(
                preferenceLabel("preferences_appearance_menu_hide_finished_toggle"),
                isOn: $hideFinishedEventsInMenu
            )

            // The greeting NAME. The greeting section itself is toggled in
            // "Dropdown layout" above; this field is disabled while it is hidden.
            TextField(
                preferenceLabel("preferences_appearance_menu_greeting_name_title"),
                text: $greetingName,
                prompt: Text("preferences_appearance_menu_greeting_name_placeholder".loco())
            )
            .disabled(!showGreetingInMenu)
            Text("preferences_appearance_menu_greeting_name_help".loco())
                .font(.caption)
                .foregroundStyle(.secondary)

            // Reminders (Dot parity). Turning this on is the ONLY place that
            // requests Reminders access — the setting only flips on if granted.
            Toggle(
                preferenceLabel("preferences_appearance_menu_show_reminders_toggle"),
                isOn: showRemindersBinding
            )
            Toggle(
                preferenceLabel("preferences_appearance_menu_reminders_include_overdue_toggle"),
                isOn: $remindersIncludeOverdue
            )
            .preferenceIndent()
            .disabled(!showRemindersInMenu)

            // The SwiftUI panel is the default dropdown; this is the escape
            // hatch back to the plain NSMenu.
            Toggle(
                preferenceLabel("preferences_appearance_menu_swiftui_dropdown_toggle"),
                isOn: $useSwiftUIDropdown
            )
            Text("preferences_appearance_menu_swiftui_dropdown_help".loco())
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
/// surface. The window's own Month/Week fold lives in its header; only the
/// weekend dimming is a persistent preference.
struct CalendarWindowDisplaySection: View {
    @Default(.dimWeekendsInCalendar) var dimWeekendsInCalendar

    var body: some View {
        Section(header: Text("preferences_appearance_calendar_window_title".loco())) {
            Toggle(
                preferenceLabel("preferences_appearance_calendar_dim_weekends_toggle"),
                isOn: $dimWeekendsInCalendar
            )
            Text("preferences_appearance_calendar_dim_weekends_help".loco())
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    DisplayTab().frame(width: 940, height: 620)
}
