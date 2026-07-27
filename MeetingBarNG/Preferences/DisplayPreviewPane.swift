//
//  DisplayPreviewPane.swift
//  MeetingBarNG
//
//  The sticky "live preview" pane on the Dropdown preferences tab (Phase 3 of
//  the Preferences overhaul). Mounts the REAL `DropdownPanelView` against a
//  fixture `StatusBarMenuState` — not a hand-copied mock — so the preview and
//  the live dropdown can never drift apart.
//
//  The menu-bar strip still uses `StatusBarPresenter.composedPresentation`,
//  the same path the real status item uses.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import AppKit
import Defaults
import SwiftUI

/// A live preview of the menu bar + dropdown that re-renders as the Display
/// settings change. The dropdown preview IS the real `DropdownPanelView`
/// (Phase 3), so any style change costs one implementation and the preview
/// cannot drift.
struct DisplayPreviewPane: View {
    // Menu-bar composition + token styles — read so the strip re-renders.
    @Default(.menuBarTokens) private var menuBarTokens
    @Default(.menuBarCountdownStyle) private var menuBarCountdownStyle
    @Default(.menuBarDateStyle) private var menuBarDateStyle
    @Default(.menuBarProgressStyle) private var menuBarProgressStyle
    @Default(.menuBarWorldClockTimeZone) private var menuBarWorldClockTimeZone
    @Default(.menuBarWorldClockLabel) private var menuBarWorldClockLabel
    @Default(.timeFormat) private var timeFormat

    // Classic status-bar keys — so the strip stays live even when the composer
    // is off (it then mirrors these via `derivedComposition`).
    @Default(.eventTitleIconFormat) private var eventTitleIconFormat
    @Default(.eventTitleFormat) private var eventTitleFormat
    @Default(.eventTimeFormat) private var eventTimeFormat
    @Default(.statusbarEventTitleLength) private var statusbarEventTitleLength

    // Dropdown toggles that affect what the preview shows — read here so the
    // body re-evaluates when they change, which re-runs PreviewFixtures.makeState.
    @Default(.hideFinishedEventsInMenu) private var hideFinishedEventsInMenu
    @Default(.showRemindersInMenu) private var showRemindersInMenu
    @Default(.showGreetingInMenu) private var showGreetingInMenu
    @Default(.showTimelineInMenu) private var showTimelineInMenu
    @Default(.showAgendaInMenu) private var showAgendaInMenu
    @Default(.showMeetingControlInMenu) private var showMeetingControlInMenu
    @Default(.showJoinSectionInMenu) private var showJoinSectionInMenu
    @Default(.showBookmarksInMenu) private var showBookmarksInMenu

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("preferences_display_preview_menu_bar_label")
                    menuBarStrip
                        .padding(.horizontal, 16)
                }

                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("preferences_display_preview_dropdown_label")
                    dropdownPreview
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("preferences_display_preview_title".loco())
                .font(.headline)
            Text("preferences_display_preview_caption".loco())
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
    }

    private func sectionLabel(_ key: String) -> some View {
        Text(key.loco())
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
    }

    // MARK: - Menu-bar strip

    /// A thin rounded strip evoking the menu bar, with the composed presentation
    /// pinned to the trailing edge (where menu-bar items live).
    private var menuBarStrip: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 12)
            chip(for: menuBarPresentation)
        }
        .padding(.trailing, 8)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        )
    }

    @ViewBuilder
    private func chip(for presentation: StatusBarPresentation) -> some View {
        HStack(spacing: 4) {
            if presentation.iconPosition == .leading {
                icon(presentation.icon)
            }
            if !presentation.title.isEmpty {
                Text(presentation.title)
                    .font(.system(size: MenuStyleConstants.defaultFontSize))
                    .foregroundStyle(.primary)
            }
            if presentation.iconPosition == .trailing {
                icon(presentation.icon)
            }
        }
    }

    @ViewBuilder
    private func icon(_ icon: StatusBarIcon) -> some View {
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

    /// The composed presentation for a representative sample event. Forces the
    /// `nextEvent` mode (calendars selected, threshold off) so the strip always
    /// shows a meaningful preview regardless of the user's actual calendar state.
    private var menuBarPresentation: StatusBarPresentation {
        let now = Date()
        var calendar = Calendar.current
        calendar.locale = I18N.instance.locale
        let sample = StatusBarEventPresentationInput(
            title: PreviewFixtures.sampleEvents.first?.title ?? "",
            startDate: now.addingTimeInterval(25 * 60),
            endDate: now.addingTimeInterval(55 * 60),
            meetingService: .zoom,
            participation: .normal
        )
        return StatusBarPresenter.composedPresentation(
            nextEvent: sample,
            composition: menuBarTokens.isEmpty ? derivedComposition : previewComposition,
            settings: previewComposedSettings,
            now: now,
            calendar: calendar
        )
    }

    /// The user's saved token composition (parsed + de-duped), mirroring
    /// `MenuBarComposition.currentIfEnabled` but reading through the observed key.
    private var previewComposition: MenuBarComposition {
        var seen = Set<MenuBarTokenKind>()
        let tokens = menuBarTokens
            .compactMap(MenuBarTokenKind.init(rawValue:))
            .filter { seen.insert($0).inserted }
        return tokens.isEmpty ? derivedComposition : MenuBarComposition(tokens: tokens)
    }

    /// Composition derived from the classic status-bar toggles, used when the
    /// composer is off — mirrors `MenuBarComposition.derivedFromLegacy` but
    /// reads the observed keys so the strip re-renders when toggles change.
    private var derivedComposition: MenuBarComposition {
        var tokens: [MenuBarTokenKind] = []
        if eventTitleIconFormat != .none { tokens.append(.icon) }
        if eventTitleFormat != .none { tokens.append(.title) }
        if eventTimeFormat != .hide { tokens.append(.countdown) }
        return tokens.isEmpty ? .standard : MenuBarComposition(tokens: tokens)
    }

    /// Mirrors `MenuBarComposedSettings.current` but reads through the observed
    /// `@Default` wrappers and forces a representative next-event mode.
    private var previewComposedSettings: MenuBarComposedSettings {
        MenuBarComposedSettings(
            presentation: StatusBarPresentationSettings(
                hasSelectedCalendars: true,
                showEventMaxTimeUntilEventEnabled: false,
                showEventMaxTimeUntilEventThreshold: 0
            ),
            title: StatusBarTitleSettings(
                titleFormat: StatusBarEventTitleFormat(eventTitleFormat),
                titleLength: statusbarEventTitleLength,
                labels: .current
            ),
            countdownStyle: CountdownStyle(rawValue: menuBarCountdownStyle) ?? .full,
            dateStyle: MenuBarDateStyle(rawValue: menuBarDateStyle) ?? .medium,
            progressStyle: MenuBarProgressStyle(rawValue: menuBarProgressStyle) ?? .day,
            use24HourClock: timeFormat == .military,
            worldClockTimeZone: TimeZone(identifier: menuBarWorldClockTimeZone) ?? .current,
            worldClockLabel: menuBarWorldClockLabel,
            weekNumberPrefix: "menu_bar_week_number_prefix".loco(),
            iconFormat: StatusBarIconFormat(eventTitleIconFormat),
            iconFormatAssetName: eventTitleIconFormat.rawValue,
            iconAssets: .production,
            tokenSeparator: "  ",
            pendingDisplay: .normal,
            tentativeDisplay: .normal
        )
    }

    // MARK: - Dropdown preview (the REAL panel)

    /// Mounts the actual `DropdownPanelView` against a fixture state. All
    /// no-op handlers — the preview is display-only, not interactive. The
    /// `@Default` wrappers above already observe the module toggles, so
    /// SwiftUI re-evaluates the body when any of them change.
    private var dropdownPreview: some View {
        let state = PreviewFixtures.makeState(
            includeFinished: !hideFinishedEventsInMenu,
            includeReminders: showRemindersInMenu
        )

        return DropdownPanelView(
            state: state,
            handlers: DropdownPanelHandlers(),
            now: PreviewFixtures.now,
            isPreview: true
        )
        .allowsHitTesting(false)
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}

#Preview {
    DisplayPreviewPane()
        .frame(width: 340, height: 620)
}
