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
//  can never accumulate leftovers. Settings search is a custom field in the
//  sidebar's top safe-area inset (not `.searchable`, which created a toolbar
//  that overlapped the first rows), backed by the hostless `SettingsIndex`.
//  `preferenceLabel()` is deleted: colons now come off at source in en.lproj,
//  not at render time.
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
    // A pane asking to show another pane ("Change in Joining"). One-shot: the
    // request is cleared as soon as it is honoured.
    private let navigation = PreferencesNavigation.shared

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
        }
        // Wide enough for the Dropdown pane's two-pane (settings + ~340pt
        // preview). Every other pane benefits from the narrower width — at
        // 1100pt a grouped form stretches with a huge dead right margin.
        .frame(minWidth: 860, minHeight: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: navigation.requestedTab) { _, requested in
            guard let requested else { return }
            selection = .tab(requested)
            searchQuery = ""
            navigation.requestedTab = nil
        }
    }

    // MARK: - Sidebar

    /// A FLAT list of the eight panes, plus one pinned footer item. The native
    /// sidebar `List(selection:)` provides the System Settings accent-pill
    /// selection and translucent material for free. No custom `foregroundStyle`
    /// is applied to the labels — the pill supplies its own contrasting content
    /// colour, and overriding it broke the selected row.
    /// The `List` MUST be the root of this view, not a child of a `VStack`.
    /// A sidebar `List` provides the sidebar role; wrapping it in a stack made
    /// the stack the sidebar instead, and the first pane ("Calendars") lost
    /// the sidebar's styling and insets.
    ///
    /// The search field attaches as a top safe-area inset so it pushes the first
    /// row down rather than overlapping it (`.searchable(placement: .sidebar)`
    /// created a toolbar that overlapped the first two rows). The footer attaches
    /// as a bottom safe-area inset so it floats above the scrolling rows without
    /// taking the `List` out of the sidebar role.
    private var sidebar: some View {
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                aboutFooterItem
            }
            .background(.bar)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                TextField(
                    "preferences_search_placeholder".loco(),
                    text: $searchQuery
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
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

    @ViewBuilder
    private var detail: some View {
        if !trimmedQuery.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PreferencesDetailHeader(
                    title: "preferences_search_results_title".loco(trimmedQuery)
                )
                SettingsSearchResults(query: trimmedQuery) { entry in
                    selection = .tab(entry.tab)
                    searchQuery = ""
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch selection {
            case .tab(let tab):
                VStack(alignment: .leading, spacing: 0) {
                    PreferencesDetailHeader(
                        title: tab.titleKey.loco(),
                        purpose: tab.purposeKey.loco()
                    )
                    preferencesTabContent(tab)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .aboutSupport:
                VStack(alignment: .leading, spacing: 0) {
                    PreferencesDetailHeader(title: "preferences_tab_about".loco())
                    AboutSupportView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// The pane title and one-line purpose shown at the top of the detail column.
/// Replaces both the `.navigationTitle` (which created an internal navigation
/// bar that clipped content in a plain `NSWindow`) and the old
/// `PreferencesPanePurpose` (which showed only the purpose line, not the title).
private struct PreferencesDetailHeader: View {
    let title: String
    var purpose: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            if let purpose {
                Text(purpose)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
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
///
/// The `.frame(maxWidth: .infinity, maxHeight: .infinity)` is load-bearing: a
/// `Form` with `.formStyle(.grouped)` is a scroll view, but without a bounded
/// frame it sizes to its content rather than the available space. Inside the
/// detail `VStack` (which stacks the purpose header above the form), that means
/// the form grows past the window's bottom edge and its scroll view never
/// activates — so the last sections are silently clipped. The frame gives the
/// scroll view a bounded height, which is what makes scrolling work.
struct PreferencesGroupedForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .focusSection()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    PreferencesView()
        .frame(width: 1180, height: 680)
}
