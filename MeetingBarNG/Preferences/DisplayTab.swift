//
//  DisplayTab.swift
//  MeetingBarNG
//
//  The "Display" preferences tab: how MeetingBarNG presents itself in the menu
//  bar and its dropdown. Phase 1 of the Preferences IA overhaul merges the
//  former menu-bar appearance tab (StatusBarSection) with the composable
//  menu-bar / dropdown builders and the dropdown display toggles.
//
//  DropdownComposerSection was moved here from MenuBuilderTab.swift, originally:
//    Created by Andrii Leitsius on 13.01.2021.
//    Copyright © 2021 Andrii Leitsius. All rights reserved.
//  Licensed under the Apache License, Version 2.0. Modified for MeetingBarNG by
//  Peter Krzyzek / Chykalophia, 2026: Phase 2 of the Preferences UX overhaul
//  moved the two menu-bar sections out into the Menu Bar pane
//  (`MenuBarTab.swift`) and deleted them here — the destructive "Customize menu
//  bar layout" toggle with them. Earlier: relocated into the Display tab and split
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
                // The menu-bar sections have left this file: they are the Menu
                // Bar pane now (`MenuBarTab.swift`).
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
