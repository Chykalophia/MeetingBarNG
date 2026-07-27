//
//  PreferencesShellV2.swift
//  MeetingBarNG
//
//  Preferences shell hosted in a SwiftUI Settings scene. The scene provides
//  proper window management — safe areas, title bar, toolbar — so
//  NavigationSplitView lays out correctly with no content clipping.
//
//  Uses .navigationTitle for the pane name (shows in the window's title bar,
//  matching System Settings and Ice 2). The detail column is just the pane
//  content — no custom header, no safeAreaInset workaround, no frame hacks.
//
//  Visual language follows Ice 2 (teddychan/ice-2): app name as a .title
//  header in the sidebar's section header, panes grouped into primary
//  and meta sections, scroll-disabled sidebar.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import SwiftUI

/// The one place the Preferences window's size range is written down.
///
/// The window (AppKit, `WindowCoordinator`) and its content (`PreferencesShellV2`
/// below) must agree: a `.frame` narrower than `minSize` leaves dead margin
/// inside the window, and a `.frame` wider than `maxSize` clips.
///
/// Widths are driven by the Dropdown pane, the only one pairing a form with a
/// second full-height column. The 240pt sidebar comes off every number, so the
/// detail column is roughly `width - 241`.
enum PreferencesWindowMetrics {
    /// Wide enough that Dropdown opens with its preview visible AND its form
    /// above `previewMinimumDetailWidth`, so the default view is the good one.
    static let defaultSize = CGSize(width: 1080, height: 680)
    /// Below this the Dropdown pane drops its preview rather than crushing the
    /// form — every other pane is single-column and comfortable well below it.
    static let minimumSize = CGSize(width: 840, height: 520)
    static let maximumSize = CGSize(width: 1400, height: 900)

    /// Detail-column width at which a pane's optional second column earns its
    /// keep. Below it the form would be narrower than its own segmented
    /// controls, which is what pushed the preview off the trailing edge.
    static let previewMinimumDetailWidth: CGFloat = 740
}

enum SidebarSelection: Hashable {
    case tab(PreferencesTab)
    case about

    var navigationTitle: String {
        switch self {
        case .tab(let tab):
            return tab.titleKey.loco()
        case .about:
            return "preferences_tab_about".loco()
        }
    }
}

struct PreferencesShellV2: View {
    @State private var selection: SidebarSelection = .tab(.defaultSelection)
    @State private var searchQuery = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    private let navigation = PreferencesNavigation.shared

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedQuery.isEmpty
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(240)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
        }
        .navigationTitle(isSearching ? "preferences_search_results_title".loco(trimmedQuery) : selection.navigationTitle)
        // `ideal*` is load-bearing, not decoration: with only min/max, SwiftUI
        // reports the MINIMUM as its fitting size, and `NSHostingController`
        // hands that to the window — which is why Preferences used to open at its
        // narrowest allowed width.
        .frame(
            minWidth: PreferencesWindowMetrics.minimumSize.width,
            idealWidth: PreferencesWindowMetrics.defaultSize.width,
            maxWidth: PreferencesWindowMetrics.maximumSize.width,
            minHeight: PreferencesWindowMetrics.minimumSize.height,
            idealHeight: PreferencesWindowMetrics.defaultSize.height,
            maxHeight: PreferencesWindowMetrics.maximumSize.height
        )
        .onChange(of: navigation.requestedTab) { _, requested in
            guard let requested else { return }
            selection = .tab(requested)
            searchQuery = ""
            navigation.requestedTab = nil
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: sidebarSelection) {
            Section {
                searchField
            }

            Section {
                ForEach(PreferencesTab.allCases) { tab in
                    Label(tab.titleKey.loco(), systemImage: tab.systemImage)
                        .tag(SidebarSelection.tab(tab))
                }
            }

            Section {
                Label("preferences_tab_about".loco(), systemImage: "info.circle")
                    .tag(SidebarSelection.about)
            }
        }
        .listStyle(.sidebar)
        .scrollDisabled(true)
    }

    /// Deliberately a row INSIDE the list rather than a `safeAreaInset` above it.
    ///
    /// As an inset it owned its own padding, which never matched the sidebar's row
    /// insets — the magnifying glass sat visibly left of every row icon beneath it
    /// — and it stacked its own vertical padding on top of the window's titlebar
    /// safe area, leaving a dead gap above the field. Worse, it painted its own
    /// `.ultraThinMaterial`, which now fights the real titlebar material the
    /// window's toolbar draws.
    ///
    /// As a list row it inherits the same insets as everything else, so it cannot
    /// drift out of alignment again. The sidebar sets `scrollDisabled`, so living
    /// in the list costs it nothing — it can never scroll away.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                "preferences_search_placeholder".loco(),
                text: $searchQuery
            )
            .textFieldStyle(.plain)
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
        .font(.system(size: 13))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
        )
        // Never a selectable row — clicking it belongs to the text field.
        .selectionDisabled()
    }

    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding(
            get: { selection },
            set: { newValue in
                if let newValue { selection = newValue }
            }
        )
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if isSearching {
            SettingsSearchResults(query: trimmedQuery) { entry in
                selection = .tab(entry.tab)
                searchQuery = ""
            }
        } else {
            switch selection {
            case .tab(let tab):
                paneContent(tab)
            case .about:
                AboutSupportView()
            }
        }
    }

    @MainActor
    @ViewBuilder
    private func paneContent(_ tab: PreferencesTab) -> some View {
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
}

#Preview {
    PreferencesShellV2()
        .frame(
            width: PreferencesWindowMetrics.defaultSize.width,
            height: PreferencesWindowMetrics.defaultSize.height
        )
}
