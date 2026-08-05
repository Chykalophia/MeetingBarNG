//
//  MenuBarTab.swift
//  MeetingBarNG
//
//  The Menu Bar pane (Preferences UX overhaul, Phase 2): what you see in the
//  macOS menu bar all day, and nothing else. No filters live here — which
//  meetings exist is decided once, on Filters.
//
//  What lives here, in order:
//    1. Preset cards — Classic / Minimal / Agenda / Info / Custom. "Custom" is
//       the label shown when no preset matches, never a mode you enter, so it
//       cannot be lost when the window closes.
//    2. The block list — Icon · Meeting title · Countdown · Clock · Date ·
//       Progress bar · Week number · World clock. Every block the menu bar can
//       hold is listed: showing ones in their left-to-right order with arrows,
//       hidden ones dimmed below. The switch is the only on/off.
//    3. Per-block gear popovers for the options each showing block has.
//       They are plain rows inside the gear so nothing is ever unreachable.
//    4. Keep the menu bar quiet until a meeting is close, with minute chips.
//    5. One line / Two lines.
//    6. Reset this section.
//
//  Two things are deliberately gone:
//
//  • "Customize menu bar layout". It was never a stored boolean: turning it off
//    ran `menuBarTokens = []`, destroying the arrangement with no undo, and
//    turning it back on reseeded from the legacy settings rather than from what
//    the user had. The builder is always on; blocks carry their own on/off, and
//    switching one off keeps it on screen, one click from returning.
//  • "Time next to the title" (`eventTimeFormat`). It was read only by the
//    classic status-bar path while sitting directly above a composer that
//    ignored it. Showing the time is now the presence of the Countdown block,
//    and show-under-title is the One line / Two lines control below.
//    `MenuBarTimeFormatDefaultsMigration` (AppSettings.swift) carries both
//    halves of anybody's stored answer across, once.
//
//  Drag-and-drop reordering is still Phase 5: this pane ships explicit arrows
//  inside `PreferencesGroupedForm`, where `.onMove` is inert because the
//  container is a `Form` and not a `List`. Per-block gear popovers are live.
//
//  Descends from `StatusBarSection` and `MenuBarComposerSection`
//  (DisplayTab.swift, moved there from AppearanceTab.swift), originally:
//    Created by Andrii Leitsius on 13.01.2021.
//    Copyright © 2021 Andrii Leitsius. All rights reserved.
//  Licensed under the Apache License, Version 2.0. Modified for MeetingBarNG by
//  Peter Krzyzek / Chykalophia, 2026: rebuilt as the Menu Bar pane — preset
//  cards, one block list holding the complete inventory, the destructive
//  composer toggle deleted, `eventTimeFormat` retired into the Countdown block
//  plus One line / Two lines, and per-pane reset.
//
//  Stored key NAMES are unchanged by the re-home, so nobody's configuration
//  resets: `menuBarTokens`, `eventTitleIconFormat`, `eventTitleFormat`,
//  `statusbarEventTitleLength`, `menuBarCountdownStyle`, `menuBarDateStyle`,
//  `menuBarProgressStyle`, `menuBarWorldClockTimeZone`,
//  `menuBarWorldClockLabel`, `showEventMaxTimeUntilEventEnabled`,
//  `showEventMaxTimeUntilEventThreshold`.
//

import Defaults
import SwiftUI

struct MenuBarTab: View {
    @Default(.menuBarTokens) private var menuBarTokens
    @Default(.menuBarTwoLineLayout) private var menuBarTwoLineLayout

    // Block options — now behind each block's gear popover.
    @Default(.eventTitleIconFormat) private var eventTitleIconFormat
    @Default(.eventTitleFormat) private var eventTitleFormat
    @Default(.statusbarEventTitleLength) private var statusbarEventTitleLength
    @Default(.menuBarCountdownStyle) private var menuBarCountdownStyle
    @Default(.menuBarCountdownLeadMinutes) private var menuBarCountdownLeadMinutes
    @Default(.menuBarDateStyle) private var menuBarDateStyle
    @Default(.menuBarProgressStyle) private var menuBarProgressStyle
    /// The MEETING indicator, not the day/year block above it — see
    /// `MeetingProgressStyle` for why the two stay separate.
    @Default(.meetingProgressStyle) private var meetingProgressStyle
    @Default(.menuBarWorldClockTimeZone) private var menuBarWorldClockTimeZone
    @Default(.menuBarWorldClockLabel) private var menuBarWorldClockLabel

    // How quiet the strip stays until a meeting is close.
    @Default(.showEventMaxTimeUntilEventEnabled) private var showEventMaxTimeUntilEventEnabled
    @Default(.showEventMaxTimeUntilEventThreshold) private var showEventMaxTimeUntilEventThreshold
    @Default(.menuBarHighlightImminentEvent) private var menuBarHighlightImminentEvent

    // The Join chip.
    @Default(.menuBarShowJoinAction) private var menuBarShowJoinAction
    @Default(.menuBarJoinActionLeadMinutes) private var menuBarJoinActionLeadMinutes

    // Which block's gear popover is open.
    @State private var gearOpenBlock: MenuBarTokenKind?

    /// Every block, showing ones first in their stored order.
    private var blocks: [MenuBarBlock] {
        MenuBarBlockList.blocks(stored: menuBarTokens)
    }

    private var showingKinds: [MenuBarTokenKind] {
        MenuBarBlockList.kinds(stored: menuBarTokens)
    }

    var body: some View {
        PreferencesGroupedForm {
            presetSection
            blocksSection
            joinActionSection
            quietSection
            meetingProgressSection
            linesSection
            PreferencesResetSection(tab: .menuBar)
        }
        // Idempotent, and the same call the app makes at launch. It matters here
        // because "Reset this section" clears the seeding flag with the blocks it
        // seeded: re-seeding on sight is what stops a reset leaving an empty
        // block list — and it keeps the pane and the menu bar telling the same
        // story, since an unseeded install is still drawn by the classic path.
        .onAppear(perform: MenuBarTimeFormatDefaultsMigration.migrateDefaultsIfNeeded)
    }

    // MARK: - Presets

    /// One-click starting points. The selected card is DERIVED from the stored
    /// blocks (`MenuBarPreset.detect`), so "Custom" is a label rather than a mode
    /// you enter — the old `@State forceCustom` meant it was silently lost every
    /// time the window closed.
    private var presetSection: some View {
        Section(header: Text("preferences_menubar_preset_title".loco())) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(MenuBarPreset.allCases, id: \.self) { preset in
                    presetCard(preset)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            helpText("preferences_menubar_preset_help")
        }
    }

    private var selectedPreset: MenuBarPreset {
        MenuBarPreset.detect(tokens: showingKinds)
    }

    @ViewBuilder
    private func presetCard(_ preset: MenuBarPreset) -> some View {
        let isSelected = selectedPreset == preset

        if preset == .custom {
            // Not a button: there is nothing to apply. It lights up when the
            // arrangement matches no named preset, which is the only honest
            // meaning "custom" can have.
            presetCardBody(preset, isSelected: isSelected)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            Button {
                menuBarTokens = preset.tokens.map(\.rawValue)
                MeetingBarLogger.preferences.info(
                    "Applied menu-bar preset \(preset.rawValue, privacy: .public)"
                )
            } label: {
                presetCardBody(preset, isSelected: isSelected)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        }
    }

    private func presetCardBody(_ preset: MenuBarPreset, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(presetName(preset))
                .font(.subheadline.weight(.medium))
            if preset != .custom {
                Text(preset.tokens.map(blockName).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .contentShape(Rectangle())
    }

    private func presetName(_ preset: MenuBarPreset) -> String {
        switch preset {
        case .classic: return "preferences_menubar_preset_classic".loco()
        case .minimal: return "preferences_menubar_preset_minimal".loco()
        case .agenda: return "preferences_menubar_preset_agenda".loco()
        case .info: return "preferences_menubar_preset_info".loco()
        case .custom: return "preferences_menubar_preset_custom".loco()
        }
    }

    // MARK: - The blocks

    /// The complete inventory, always. A block that is off stays listed and
    /// dimmed, so "off" can never read as "gone" — and there is no "Add block"
    /// menu to go looking for, because nothing was ever removed.
    private var blocksSection: some View {
        Section(header: Text("preferences_menubar_blocks_title".loco())) {
            helpText("preferences_menubar_blocks_help")

            ForEach(Array(blocks.enumerated()), id: \.element.kind) { pair in
                blockRow(pair.element, index: pair.offset)
            }
        }
    }

    private func blockRow(_ block: MenuBarBlock, index: Int) -> some View {
        HStack(spacing: 6) {
            Label(blockName(block.kind), systemImage: blockSymbol(block.kind))
                .foregroundStyle(block.isOn ? .primary : .secondary)

            Spacer()

            if hasGear(block.kind) {
                Button {
                    gearOpenBlock = (gearOpenBlock == block.kind) ? nil : block.kind
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .disabled(!block.isOn)
                .help("preferences_menubar_block_configure".loco())
                .popover(isPresented: gearBinding(for: block.kind)) {
                    blockGearContent(block.kind)
                        .frame(width: 320)
                        .padding(16)
                }
            }

            Button {
                menuBarTokens = MenuBarBlockList.moved(stored: menuBarTokens, kind: block.kind, by: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(!block.isOn || index == 0)
            .help("preferences_menubar_block_move_up".loco())

            Button {
                menuBarTokens = MenuBarBlockList.moved(stored: menuBarTokens, kind: block.kind, by: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(!block.isOn || index == showingKinds.count - 1)
            .help("preferences_menubar_block_move_down".loco())

            Toggle("", isOn: blockSwitch(block.kind))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(Text(blockName(block.kind)))
        }
    }

    /// Blocks that have configurable options get a gear; others (clock, week
    /// number) are just on/off and show no gear.
    private func hasGear(_ kind: MenuBarTokenKind) -> Bool {
        switch kind {
        case .icon, .title, .countdown, .date, .progress, .worldClock:
            return true
        case .clock, .weekNumber:
            return false
        }
    }

    private func gearBinding(for kind: MenuBarTokenKind) -> Binding<Bool> {
        Binding(
            get: { gearOpenBlock == kind },
            set: { isOn in gearOpenBlock = isOn ? kind : nil }
        )
    }

    /// The popover content for a block's gear — only the options that belong
    /// to that block, so the pane stays calm by default and deep on demand.
    @ViewBuilder
    private func blockGearContent(_ kind: MenuBarTokenKind) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(blockName(kind))
                .font(.headline)
                .foregroundStyle(.primary)

            switch kind {
            case .icon:
                Picker("preferences_menubar_icon_title".loco(), selection: $eventTitleIconFormat) {
                    iconOption(.calendar, labelKey: "preferences_menubar_icon_calendar")
                    iconOption(.appicon, labelKey: "preferences_menubar_icon_app")
                    iconOption(.eventtype, labelKey: "preferences_menubar_icon_service")
                    iconOption(.none, labelKey: "preferences_menubar_icon_none")
                }
                if eventTitleIconFormat == .none {
                    helpText("preferences_menubar_icon_none_help")
                }

            case .title:
                Picker("preferences_menubar_title_title".loco(), selection: $eventTitleFormat) {
                    Text("preferences_menubar_title_event".loco()).tag(EventTitleFormat.show)
                    Text("preferences_menubar_title_generic".loco()).tag(EventTitleFormat.generic)
                    Text("preferences_menubar_title_dot".loco()).tag(EventTitleFormat.dot)
                    Text("preferences_menubar_title_none".loco()).tag(EventTitleFormat.none)
                }
                Divider()
                Text("preferences_menubar_title_shorten_title".loco())
                    .font(.subheadline.weight(.medium))
                PresetNumberPicker(
                    presets: [20, 30, 50, 80],
                    presetLabel: { "\($0)" },
                    customLabel: "preferences_preset_custom".loco(),
                    value: $statusbarEventTitleLength,
                    range: statusbarEventTitleLengthLimits.min ... statusbarEventTitleLengthLimits.max,
                    step: 5,
                    stepperLabel: { "preferences_menubar_title_shorten_stepper".loco($0) },
                    example: "preferences_menubar_title_shorten_example".loco(),
                    isEnabled: eventTitleFormat == .show
                )

            case .countdown:
                Picker(
                    "preferences_menubar_countdown_style_title".loco(),
                    selection: countdownStyle
                ) {
                    Text("preferences_menubar_countdown_style_compact".loco()).tag(CountdownStyle.compact)
                    Text("preferences_menubar_countdown_style_full".loco()).tag(CountdownStyle.full)
                    Text("preferences_menubar_countdown_style_digital".loco()).tag(CountdownStyle.digital)
                }
                Divider()
                Text("preferences_menubar_countdown_lead_title".loco())
                    .font(.subheadline.weight(.medium))
                PresetNumberPicker(
                    presets: [0, 15, 30, 60, 120],
                    // 0 is not "0 minutes before", it is "no limit" — the block's
                    // original behaviour, and the one preset that has to be
                    // spelled out rather than shown as a number.
                    presetLabel: { $0 == 0 ? "preferences_menubar_countdown_lead_always".loco() : "\($0)" },
                    customLabel: "preferences_preset_custom".loco(),
                    value: $menuBarCountdownLeadMinutes,
                    range: 0 ... 720,
                    step: 5,
                    stepperLabel: { "preferences_menubar_countdown_lead_stepper".loco($0) },
                    example: "preferences_menubar_countdown_lead_example".loco()
                )

            case .date:
                Picker("preferences_menubar_date_style_title".loco(), selection: dateStyle) {
                    Text("preferences_menubar_date_style_weekday".loco()).tag(MenuBarDateStyle.weekday)
                    Text("preferences_menubar_date_style_medium".loco()).tag(MenuBarDateStyle.medium)
                    Text("preferences_menubar_date_style_short".loco()).tag(MenuBarDateStyle.short)
                }

            case .progress:
                Picker("preferences_menubar_progress_style_title".loco(), selection: progressStyle) {
                    Text("preferences_menubar_progress_style_day".loco()).tag(MenuBarProgressStyle.day)
                    Text("preferences_menubar_progress_style_year".loco()).tag(MenuBarProgressStyle.year)
                }

            case .worldClock:
                Picker(
                    "preferences_menubar_world_clock_timezone_title".loco(),
                    selection: $menuBarWorldClockTimeZone
                ) {
                    ForEach(TimeZone.knownTimeZoneIdentifiers.sorted(), id: \.self) { identifier in
                        Text(identifier).tag(identifier)
                    }
                }
                Divider()
                TextField(
                    "preferences_menubar_world_clock_label_title".loco(),
                    text: $menuBarWorldClockLabel,
                    prompt: Text("preferences_menubar_world_clock_label_placeholder".loco())
                )

            case .clock, .weekNumber:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Turning a block off removes it from the showing order and nothing else:
    /// its options live in their own keys and survive untouched, which is what
    /// makes the switch safe to flip.
    private func blockSwitch(_ kind: MenuBarTokenKind) -> Binding<Bool> {
        Binding(
            get: { showingKinds.contains(kind) },
            set: { isOn in
                menuBarTokens = MenuBarBlockList.setting(stored: menuBarTokens, kind: kind, isOn: isOn)
            }
        )
    }

    private func blockName(_ kind: MenuBarTokenKind) -> String {
        switch kind {
        case .icon: return "preferences_menubar_block_icon".loco()
        case .title: return "preferences_menubar_block_title".loco()
        case .countdown: return "preferences_menubar_block_countdown".loco()
        case .date: return "preferences_menubar_block_date".loco()
        case .clock: return "preferences_menubar_block_clock".loco()
        case .progress: return "preferences_menubar_block_progress".loco()
        case .weekNumber: return "preferences_menubar_block_week_number".loco()
        case .worldClock: return "preferences_menubar_block_world_clock".loco()
        }
    }

    private func blockSymbol(_ kind: MenuBarTokenKind) -> String {
        switch kind {
        case .icon: return "app"
        case .title: return "textformat"
        case .countdown: return "timer"
        case .date: return "calendar"
        case .clock: return "clock"
        case .progress: return "chart.bar.xaxis"
        case .weekNumber: return "number"
        case .worldClock: return "globe"
        }
    }

    // MARK: - Icon helper (used by the gear popover)

    private func iconOption(_ format: EventTitleIconFormat, labelKey: String) -> some View {
        HStack {
            Image(nsImage: iconImage(named: format.rawValue))
                .resizable()
                .frame(width: 16, height: 16)
            Text(labelKey.loco())
        }
        .tag(format)
    }

    private func iconImage(named name: String) -> NSImage {
        let image = MenuStyleConstants.iconNamed(name)
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    // MARK: - Join chip

    /// The one thing in the menu bar you can press.
    ///
    /// Not a block, and its own section rather than a row in the block list, for
    /// a reason worth stating: every block is a piece of information you arrange,
    /// and this is a control. It has no place in the order — a button goes at the
    /// end — and it is the only part of the item where a click does something
    /// other than open the dropdown, which is worth its own heading.
    ///
    /// The lead time is a key of its own rather than the shared
    /// `eventActionHighlightMinutes`: that one decides how things LOOK once a
    /// meeting is near, and folding the chip into it would mean you could not
    /// keep the bolding without also taking the button.
    private var joinActionSection: some View {
        Section(header: Text("preferences_menubar_join_action_title".loco())) {
            Toggle(
                "preferences_menubar_join_action_toggle".loco(),
                isOn: $menuBarShowJoinAction
            )
            .annotation("preferences_menubar_join_action_help")

            PresetNumberPicker(
                presets: [0, 2, 5, 15],
                // Same presets and same spelled-out zero as the dropdown's
                // highlight lead time, which is the control this most resembles.
                // 0 is not "no lead time" to a reader, it is "only once it runs".
                presetLabel: { $0 == 0 ? "preferences_menubar_join_action_now".loco() : "\($0)" },
                customLabel: "preferences_preset_custom".loco(),
                value: $menuBarJoinActionLeadMinutes,
                range: 0 ... 120,
                step: 1,
                stepperLabel: { "preferences_menubar_join_action_stepper".loco($0) },
                example: "preferences_menubar_join_action_example".loco(),
                isEnabled: menuBarShowJoinAction
            )
        }
    }

    // MARK: - Quiet until a meeting is close

    private var quietSection: some View {
        Section {
            Toggle(
                "preferences_menubar_quiet_toggle".loco(),
                isOn: $showEventMaxTimeUntilEventEnabled
            )

            PresetNumberPicker(
                presets: [15, 30, 60, 120, 240],
                presetLabel: minutesPresetLabel,
                customLabel: "preferences_preset_custom".loco(),
                value: $showEventMaxTimeUntilEventThreshold,
                range: 5 ... 720,
                step: 5,
                stepperLabel: { "preferences_menubar_quiet_stepper".loco($0) },
                example: "preferences_menubar_quiet_example".loco(),
                isEnabled: showEventMaxTimeUntilEventEnabled
            )

            Divider()

            // Deliberately no threshold control of its own: it shares
            // `eventActionHighlightMinutes` with the dropdown's action buttons,
            // set on the Dropdown page. Two knobs for one notion of "now-ish"
            // would only let them disagree.
            Toggle(
                "preferences_menubar_highlight_imminent_toggle".loco(),
                isOn: $menuBarHighlightImminentEvent
            )
            .annotation("preferences_menubar_highlight_imminent_help")
        }
    }

    // MARK: - Meeting progress

    /// How the strip shows the next meeting approaching.
    ///
    /// Its own section rather than an option on the `.progress` block: that block
    /// draws a day/year bar and is event-independent, while this decorates the
    /// whole item and only exists when there is a meeting. Putting them together
    /// would suggest picking one excludes the other, which is false.
    private var meetingProgressSection: some View {
        Section(header: Text("preferences_menubar_meeting_progress_title".loco())) {
            Picker(
                "preferences_menubar_meeting_progress_style_title".loco(),
                selection: meetingProgressStyleBinding
            ) {
                Text("preferences_menubar_meeting_progress_none".loco())
                    .tag(MeetingProgressStyle.none)
                Text("preferences_menubar_meeting_progress_underline".loco())
                    .tag(MeetingProgressStyle.underline)
                Text("preferences_menubar_meeting_progress_ring".loco())
                    .tag(MeetingProgressStyle.ring)
                Text("preferences_menubar_meeting_progress_capsule".loco())
                    .tag(MeetingProgressStyle.capsule)
                Text("preferences_menubar_meeting_progress_bar".loco())
                    .tag(MeetingProgressStyle.bar)
            }
            .annotation("preferences_menubar_meeting_progress_help")
        }
    }

    /// Bridges the raw-string Default to the hostless enum, like the dropdown's
    /// density picker. An unrecognised stored value reads back as `.none` rather
    /// than leaving the picker with no selection.
    private var meetingProgressStyleBinding: Binding<MeetingProgressStyle> {
        Binding(
            get: { MeetingProgressStyle(rawValue: meetingProgressStyle) ?? .none },
            set: { meetingProgressStyle = $0.rawValue }
        )
    }

    /// A look-ahead preset as a short duration chip: "15m", "1h", "2h".
    private func minutesPresetLabel(_ minutes: Int) -> String {
        minutes < 60
            ? "preferences_preset_minutes_short".loco(minutes)
            : "preferences_preset_hours_short".loco(minutes / 60)
    }

    // MARK: - One line / Two lines

    /// The surviving half of the retired `eventTimeFormat` picker: on two lines
    /// the meeting title is the headline and every other block sits under it.
    /// Only meaningful once there is a title to stack under, so the row is
    /// disabled while the Meeting title block is off.
    private var linesSection: some View {
        Section {
            Picker("preferences_menubar_lines_title".loco(), selection: $menuBarTwoLineLayout) {
                Text("preferences_menubar_lines_one".loco()).tag(false)
                Text("preferences_menubar_lines_two".loco()).tag(true)
            }
            .disabled(!showingKinds.contains(.title))
        }
    }

    // MARK: - Bindings

    private var countdownStyle: Binding<CountdownStyle> {
        Binding(
            get: { CountdownStyle(rawValue: menuBarCountdownStyle) ?? .full },
            set: { menuBarCountdownStyle = $0.rawValue }
        )
    }

    private var dateStyle: Binding<MenuBarDateStyle> {
        Binding(
            get: { MenuBarDateStyle(rawValue: menuBarDateStyle) ?? .medium },
            set: { menuBarDateStyle = $0.rawValue }
        )
    }

    private var progressStyle: Binding<MenuBarProgressStyle> {
        Binding(
            get: { MenuBarProgressStyle(rawValue: menuBarProgressStyle) ?? .day },
            set: { menuBarProgressStyle = $0.rawValue }
        )
    }

    // MARK: - Helpers

    private func helpText(_ key: String) -> some View {
        PreferencesHelpText(key: key)
    }
}

#Preview {
    MenuBarTab().frame(width: 700, height: 700)
}
