//
//  MenuBuilderTab.swift
//  MeetingBarNG
//
//  The "Menu Builder" preferences tab: a Dot-style visual builder that houses
//  both the composable menu-bar TITLE builder (moved here from AppearanceTab)
//  and a new composable menu-DROPDOWN builder. Feature only — no AI/LLM, no
//  natural language, no voice.
//

import Defaults
import SwiftUI

struct MenuBuilderTab: View {
    var body: some View {
        PreferencesGroupedForm {
            // The menu-bar TITLE composer (its struct still lives in
            // AppearanceTab.swift; only its usage moved here).
            MenuBarComposerSection()
            // The menu-DROPDOWN section composer (MeetingBarNG).
            DropdownComposerSection()
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

#Preview {
    MenuBuilderTab().frame(width: 700, height: 620)
}
