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
//  minimum size so the Display tab's two-pane settings + live preview fit.
//  Preferences UX overhaul Phase 0 (truth pass): the deployment floor is macOS 15
//  (`Package.swift`), so the `#available(macOS 13/14, *)` dispatch, the macOS 12
//  `legacyLayout`, the `PreferencesGroupedForm` ScrollView fallback and the
//  `ModernPreferencesLayout` wrapper were all unreachable code and are deleted;
//  the sidebar minimum widens 215 → 225 per the macOS 26 sidebar guidance.
//
import SwiftUI

struct PreferencesView: View {
    // Non-optional: a settings window always has exactly one active tab.
    // An optional selection binding let NavigationSplitView seed the sidebar
    // highlight out of sync with the detail on first appearance.
    @State private var selectedTab: PreferencesTab = .defaultSelection
    // Pinned to `.all` so both columns are visible from the first frame; the
    // sidebar toggle is removed below, so the sidebar can never be collapsed.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 225, ideal: 235, max: 260)
        } detail: {
            preferencesTabContent(selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(selectedTab.titleKey.loco())
        }
        .navigationSplitViewStyle(.balanced)
        // Wide enough for the Display tab's two-pane (settings + ~340pt preview).
        .frame(minWidth: 1100, minHeight: 560)
    }

    // The native sidebar list: `List(selection:)` provides the System Settings
    // accent-pill selection and translucent material for free. No custom
    // `foregroundStyle` is applied to the labels — the pill supplies its own
    // contrasting content colour, and overriding it broke the selected row.
    private var sidebar: some View {
        List(selection: $selectedTab) {
            ForEach(PreferencesSidebarSection.allCases, id: \.self) { section in
                Section(section.titleKey.loco()) {
                    ForEach(section.tabs, id: \.self) { tab in
                        Label(tab.titleKey.loco(), systemImage: tab.systemImage)
                            .tag(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // Makes the sidebar truly non-collapsible (macOS 14+, below the floor).
        // https://developer.apple.com/documentation/swiftui/view/toolbar(removing:)
        .toolbar(removing: .sidebarToggle)
    }
}

/// Builds the detail content for a preferences tab.
@MainActor
@ViewBuilder
private func preferencesTabContent(_ tab: PreferencesTab) -> some View {
    switch tab {
    case .general:
        GeneralTab()
    case .calendars:
        CalendarsTab()
    case .display:
        DisplayTab()
    case .events:
        EventsTab()
    case .meetings:
        MeetingsTab()
    case .notifications:
        NotificationsTab()
    case .advanced:
        AdvancedTab()
    }
}

/// Returns a row label for the given localization key with any trailing
/// colon removed. Legacy strings include colons ("All-day events:") that the
/// grouped-form layout doesn't use; trimming at presentation level keeps all
/// locales consistent without touching translation files.
func preferenceLabel(_ key: String) -> String {
    var label = key.loco().trimmingCharacters(in: .whitespaces)
    while let last = label.last, last == ":" || last == "：" {
        label.removeLast()
    }
    return label
}

/// Shared container for preferences tabs: a grouped form matching the
/// System Settings look. Tabs built on this manage their own scrolling.
///
/// Note for the builder work in later phases: this is a `Form`, not a `List`,
/// so `ForEach(...).onMove` inside it is inert (see `MeetingsTab`'s bookmarks).
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
