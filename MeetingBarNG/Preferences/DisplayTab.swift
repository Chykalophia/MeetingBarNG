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
//  the dropdown display toggles into `DropdownDisplaySection`.
//

import Defaults
import SwiftUI

struct DisplayTab: View {
    var body: some View {
        PreferencesGroupedForm {
            // "Menu bar" — the classic status-bar icon/title/time controls.
            StatusBarSection()
            // "Menu bar layout" — composable menu-bar token builder.
            MenuBarComposerSection()
            // "Dropdown layout" — composable dropdown section builder.
            DropdownComposerSection()
            // "Dropdown" — dropdown display toggles (timeline, greeting, …).
            DropdownDisplaySection()
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

            HStack {
                Spacer()
                Stepper(
                    value: $statusbarEventTitleLength,
                    in: statusbarEventTitleLengthLimits.min ... statusbarEventTitleLengthLimits.max,
                    step: 5
                ) {
                    Text(
                        "preferences_appearance_status_bar_title_shorten_stepper".loco(
                            statusbarEventTitleLength)
                    )
                    .monospacedDigit()
                }
                .fixedSize()
            }
            .preferenceIndent()
            .disabled(eventTitleFormat != .show)

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

            HStack {
                Spacer()
                Stepper(
                    value: $showEventMaxTimeUntilEventThreshold,
                    in: 5 ... 720,
                    step: 5
                ) {
                    Text(
                        "preferences_appearance_status_bar_next_event_stepper".loco(
                            showEventMaxTimeUntilEventThreshold)
                    )
                    .monospacedDigit()
                }
                .fixedSize()
            }
            .preferenceIndent()
            .disabled(!showEventMaxTimeUntilEventEnabled)

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

            Section(header: Text("preferences_appearance_menu_bar_composer_preview_label".loco())) {
                previewChip
            }
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

    @ViewBuilder
    private var previewChip: some View {
        let presentation = previewPresentation
        HStack(spacing: 4) {
            if presentation.iconPosition == .leading {
                previewIcon(presentation.icon)
            }
            if !presentation.title.isEmpty {
                Text(presentation.title)
                    .font(.system(size: MenuStyleConstants.defaultFontSize))
            }
            if presentation.iconPosition == .trailing {
                previewIcon(presentation.icon)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.08))
        )
    }

    @ViewBuilder
    private func previewIcon(_ icon: StatusBarIcon) -> some View {
        switch icon {
        case .asset(let name):
            Image(nsImage: MenuStyleConstants.iconNamed(name))
                .resizable()
                .frame(width: 16, height: 16)
        case .meetingService(let service):
            Image(nsImage: getIconForMeetingService(service))
                .resizable()
                .frame(width: 16, height: 16)
        case .none:
            EmptyView()
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

    private var previewPresentation: StatusBarPresentation {
        let now = Date()
        var calendar = Calendar.current
        calendar.locale = I18N.instance.locale
        let sample = StatusBarEventPresentationInput(
            title: "preferences_appearance_menu_bar_preview_sample_event".loco(),
            startDate: now.addingTimeInterval(25 * 60),
            endDate: now.addingTimeInterval(55 * 60),
            // A representative service so the "event type" icon format previews a
            // real glyph rather than the no-session fallback.
            meetingService: .zoom,
            participation: .normal
        )
        return StatusBarPresenter.composedPresentation(
            nextEvent: sample,
            composition: MenuBarComposition(tokens: tokens),
            settings: .current,
            now: now,
            calendar: calendar
        )
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
                    menuBarTokens = []
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
        Set(DropdownModule.allCases.filter { isEnabled($0) }.map(\.rawValue))
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

        Section(header: Text("preferences_appearance_menu_bar_composer_preview_label".loco())) {
            previewCard
        }
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

    @ViewBuilder
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(visibleModules, id: \.self) { module in
                previewRow(symbol: moduleSymbol(module), name: moduleName(module), pinned: false)
            }
            // The Preferences footer is pinned, never a module — shown here so the
            // preview matches the real dropdown and the safety guarantee is visible.
            previewRow(
                symbol: "gearshape",
                name: "preferences_menu_builder_dropdown_module_preferences".loco(),
                pinned: true
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func previewRow(symbol: String, name: String, pinned: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(pinned ? .secondary : .primary)
            Text(name)
                .foregroundStyle(pinned ? .secondary : .primary)
            if pinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: MenuStyleConstants.defaultFontSize))
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

/// The dropdown display toggles that are not part of the composable builder:
/// timeline, hide-finished, the greeting header + name, and the Reminders
/// toggles. Split out of the former `MenuSection` (AppearanceTab.swift) so the
/// event-row detail toggles can live on the Events tab instead.
struct DropdownDisplaySection: View {
    @Default(.showTimelineInMenu) var showTimelineInMenu
    @Default(.hideFinishedEventsInMenu) var hideFinishedEventsInMenu
    @Default(.showGreetingInMenu) var showGreetingInMenu
    @Default(.greetingName) var greetingName
    @Default(.showRemindersInMenu) var showRemindersInMenu
    @Default(.remindersIncludeOverdue) var remindersIncludeOverdue

    var body: some View {
        Section(header: Text("preferences_appearance_menu_title".loco())) {
            Toggle(
                preferenceLabel("preferences_appearance_menu_show_timeline_toggle"),
                isOn: $showTimelineInMenu
            )
            Toggle(
                preferenceLabel("preferences_appearance_menu_hide_finished_toggle"),
                isOn: $hideFinishedEventsInMenu
            )
            Toggle(
                preferenceLabel("preferences_appearance_menu_show_greeting_toggle"),
                isOn: $showGreetingInMenu
            )
            TextField(
                preferenceLabel("preferences_appearance_menu_greeting_name_title"),
                text: $greetingName,
                prompt: Text("preferences_appearance_menu_greeting_name_placeholder".loco())
            )
            .preferenceIndent()
            .disabled(!showGreetingInMenu)

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

#Preview {
    DisplayTab().frame(width: 700, height: 620)
}
