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
        .frame(minWidth: 825, maxWidth: 1150, minHeight: 500, maxHeight: 750)
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
        .safeAreaInset(edge: .top, spacing: 6) {
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
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
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
        .frame(width: 900, height: 625)
}
