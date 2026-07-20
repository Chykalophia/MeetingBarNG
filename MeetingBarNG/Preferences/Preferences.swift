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
//  shared PreferencesDesign card/callout/indent language.
//
import SwiftUI

struct PreferencesView: View {
    // Non-optional: a settings window always has exactly one active tab.
    // An optional selection binding let NavigationSplitView seed the sidebar
    // highlight out of sync with the detail on first appearance.
    @State private var selectedTab: PreferencesTab = .defaultSelection

    var body: some View {
        if #available(macOS 13.0, *) {
            // The modern split view owns a `NavigationSplitViewVisibility`
            // (macOS 13+ only), so it lives in its own availability-gated view
            // to keep the macOS 12 `legacyLayout` compiling.
            ModernPreferencesLayout(selectedTab: $selectedTab)
        } else {
            legacyLayout
        }
    }

    // macOS 12 fallback: NavigationSplitView is unavailable, so keep the manual
    // split with hand-rolled selection styling. Already non-collapsible.
    private var legacyLayout: some View {
        HStack(spacing: 0) {
            List {
                ForEach(PreferencesSidebarSection.allCases, id: \.self) { section in
                    Section(header: Text(section.titleKey.loco())) {
                        ForEach(section.tabs, id: \.self) { tab in
                            Button {
                                selectedTab = tab
                            } label: {
                                Label(tab.titleKey.loco(), systemImage: tab.systemImage)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 7)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(selectedTab == tab ? Color.white : Color.primary)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                                    .padding(.horizontal, 6)
                            )
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180, idealWidth: 190, maxWidth: 220)

            Divider()

            preferencesTabContent(selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

/// The macOS 13+ layout: a `NavigationSplitView` pinned open so the sidebar can
/// never be collapsed. It owns the `NavigationSplitViewVisibility` state (a
/// macOS 13-only type), so isolating it here keeps `PreferencesView`'s macOS 12
/// `legacyLayout` compiling at the deployment floor.
@available(macOS 13.0, *)
private struct ModernPreferencesLayout: View {
    @Binding var selectedTab: PreferencesTab
    // Pinned to `.all`: on macOS 14+ the toggle button is removed entirely, and
    // seeding the binding open keeps both columns visible on macOS 13.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 215, ideal: 230, max: 260)
        } detail: {
            preferencesTabContent(selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(selectedTab.titleKey.loco())
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 520)
    }

    // The native sidebar list: `List(selection:)` provides the System Settings
    // accent-pill selection and translucent material for free, so the custom
    // Button / listRowBackground styling the legacy layout needs is gone here.
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
        .pinnedSidebarToggleRemoved()
    }
}

@available(macOS 13.0, *)
private extension View {
    /// Removes the automatic sidebar-toggle button on macOS 14+ (making the
    /// sidebar truly non-collapsible); on macOS 13 the API is unavailable, so
    /// the view is returned unchanged and the pinned `columnVisibility` binding
    /// keeps the sidebar open.
    @ViewBuilder
    func pinnedSidebarToggleRemoved() -> some View {
        if #available(macOS 14.0, *) {
            toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}

/// Builds the detail content for a preferences tab. Shared by the modern
/// `NavigationSplitView` layout and the macOS 12 `legacyLayout`.
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
/// System Settings look on macOS 13+, with a plain scrollable form as the
/// macOS 12 fallback. Tabs built on this manage their own scrolling.
struct PreferencesGroupedForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 13.0, *) {
            Form { content }
                .formStyle(.grouped)
        } else {
            ScrollView {
                Form { content }
                    .padding(20)
            }
        }
    }
}

#Preview {
    PreferencesView()
        .frame(width: 860, height: 620)
}
