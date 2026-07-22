//
//  PreferencesView.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 14.05.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
//  Modified for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026:
//  drop the StoreKit patronage service threaded through the preferences window;
//  pin the NavigationSplitView sidebar open (non-collapsible) and adopt the
//  shared PreferencesDesign card/callout/indent language; widen the window
//  minimum size so the Dropdown tab's two-pane settings + live preview fit.
//  Preferences UX overhaul Phase 0 (truth pass) deleted the macOS 12/13 fallbacks.
//  Phase 2 (the IA restructure) replaces the seven old tabs with eight panes in a
//  FLAT sidebar — `PreferencesSidebarSection` is gone, because grouping eight
//  concrete names under abstract nouns ("Setup", "Experience") rebuilt exactly
//  the "everything is miscellaneous" problem the overhaul exists to remove.
//  About & Support becomes a pinned sidebar FOOTER item rather than a pane, so it
//  can never accumulate leftovers. Settings search (`.searchable`) is present on
//  every pane, backed by the hostless `SettingsIndex`. `preferenceLabel()` is
//  deleted: colons now come off at source in en.lproj, not at render time.
//
import SwiftUI

/// What the sidebar currently points at. About & Support is deliberately not a
/// `PreferencesTab` — it is a footer item, not a settings pane.
enum PreferencesSelection: Hashable {
    case tab(PreferencesTab)
    case aboutSupport
}

struct PreferencesView: View {
    // Non-optional: a settings window always points at exactly one thing.
    @State private var selection: PreferencesSelection = .tab(.defaultSelection)
    @State private var searchQuery = ""
    // Pinned to `.all` so both columns are visible from the first frame; the
    // sidebar toggle is removed below, so the sidebar can never be collapsed.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 225, ideal: 235, max: 260)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(navigationTitle)
        }
        .navigationSplitViewStyle(.balanced)
        // Wide enough for the Dropdown pane's two-pane (settings + ~340pt
        // preview). Phase 3 replaces that preview and drops this to 860.
        .frame(minWidth: 1100, minHeight: 560)
    }

    // MARK: - Sidebar

    /// A FLAT list of the eight panes, plus one pinned footer item. The native
    /// sidebar `List(selection:)` provides the System Settings accent-pill
    /// selection and translucent material for free. No custom `foregroundStyle`
    /// is applied to the labels — the pill supplies its own contrasting content
    /// colour, and overriding it broke the selected row.
    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: tabSelection) {
                ForEach(PreferencesTab.allCases) { tab in
                    Label(tab.titleKey.loco(), systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .listStyle(.sidebar)
            // Makes the sidebar truly non-collapsible (macOS 14+, below the floor).
            // https://developer.apple.com/documentation/swiftui/view/toolbar(removing:)
            .toolbar(removing: .sidebarToggle)

            Divider()
            aboutFooterItem
        }
        .searchable(
            text: $searchQuery,
            placement: .sidebar,
            prompt: Text("preferences_search_placeholder".loco())
        )
    }

    /// Bridges the two-case selection to the `List`'s single-type selection:
    /// picking the footer item deselects every row.
    private var tabSelection: Binding<PreferencesTab?> {
        Binding(
            get: {
                if case .tab(let tab) = selection { return tab }
                return nil
            },
            set: { newValue in
                if let newValue { selection = .tab(newValue) }
            }
        )
    }

    private var aboutFooterItem: some View {
        let isSelected = selection == .aboutSupport
        return Button {
            selection = .aboutSupport
        } label: {
            Label("preferences_tab_about".loco(), systemImage: "info.circle")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Detail

    private var navigationTitle: String {
        if !trimmedQuery.isEmpty {
            return "preferences_search_results_title".loco(trimmedQuery)
        }
        switch selection {
        case .tab(let tab): return tab.titleKey.loco()
        case .aboutSupport: return "preferences_tab_about".loco()
        }
    }

    @ViewBuilder
    private var detail: some View {
        if !trimmedQuery.isEmpty {
            SettingsSearchResults(query: trimmedQuery) { entry in
                selection = .tab(entry.tab)
                searchQuery = ""
            }
        } else {
            switch selection {
            case .tab(let tab):
                VStack(alignment: .leading, spacing: 0) {
                    PreferencesPanePurpose(tab: tab)
                    preferencesTabContent(tab)
                }
            case .aboutSupport:
                AboutSupportView()
            }
        }
    }
}

/// The one-line "what this pane is for" strip under the window title. Eight
/// panes are only holdable if each states its own purpose.
private struct PreferencesPanePurpose: View {
    let tab: PreferencesTab

    var body: some View {
        Text(tab.purposeKey.loco())
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }
}

/// Builds the detail content for a preferences pane.
@MainActor
@ViewBuilder
private func preferencesTabContent(_ tab: PreferencesTab) -> some View {
    switch tab {
    case .calendars:
        CalendarsTab()
    case .filters:
        FiltersTab()
    case .menuBar:
        MenuBarTab()
    case .dropdown:
        DropdownTab()
    case .calendarWindow:
        CalendarWindowTab()
    case .joining:
        JoiningTab()
    case .alerts:
        AlertsTab()
    case .general:
        GeneralTab()
    }
}

/// Returns a row label with any trailing colon removed.
///
/// Phase 2 strips colons at source in `en.lproj`, so for migrated strings this
/// is a no-op. It stays until every pane has been through the migration —
/// deleting it while ~37 call sites still read un-migrated keys would print
/// "All-day events:" inside a grouped form that supplies its own alignment.
/// Remove it once the last caller is gone, not before.
func preferenceLabel(_ key: String) -> String {
    var label = key.loco().trimmingCharacters(in: .whitespaces)
    while let last = label.last, last == ":" || last == "：" {
        label.removeLast()
    }
    return label
}

/// Shared container for preferences panes: a grouped form matching the
/// System Settings look. Panes built on this manage their own scrolling.
///
/// Note for the builder work in later phases: this is a `Form`, not a `List`,
/// so `ForEach(...).onMove` inside it is inert — which is why every reorder
/// control in Preferences is an explicit up/down button until Phase 5 moves the
/// builders into a real `List`.
struct PreferencesGroupedForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
    }
}

#Preview {
    PreferencesView()
        .frame(width: 1180, height: 680)
}
