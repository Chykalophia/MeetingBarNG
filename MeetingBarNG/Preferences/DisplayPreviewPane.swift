//
//  DisplayPreviewPane.swift
//  MeetingBarNG
//
//  The sticky "live preview" pane on the Display preferences tab (Phase 2 of the
//  Preferences overhaul). Renders, top to bottom: a small strip mimicking the
//  menu bar (the composed menu-bar presentation for a sample event) and a mock
//  dropdown card that reflects the resolved dropdown-module order plus the main
//  toggles. It is a STATIC representative mock — it never instantiates the real
//  NSMenu — but it reads the same `@Default` keys the status bar renders from, so
//  changing any Display setting updates it instantly.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import AppKit
import Defaults
import SwiftUI

/// A live, representative preview of the menu bar + dropdown that re-renders as
/// the Display settings change. Reuses the composed-presentation logic
/// (`StatusBarPresenter.composedPresentation`) for the menu-bar strip — the same
/// path the real status item uses — and `DropdownCompositionPolicy` for the
/// dropdown-module order, so it can never drift from the real menu.
struct DisplayPreviewPane: View {
    // Menu-bar composition + token styles.
    @Default(.menuBarTokens) private var menuBarTokens
    @Default(.menuBarCountdownStyle) private var menuBarCountdownStyle
    @Default(.menuBarDateStyle) private var menuBarDateStyle
    @Default(.menuBarProgressStyle) private var menuBarProgressStyle
    @Default(.menuBarWorldClockTimeZone) private var menuBarWorldClockTimeZone
    @Default(.menuBarWorldClockLabel) private var menuBarWorldClockLabel
    @Default(.timeFormat) private var timeFormat

    // Classic status-bar keys — so the strip stays live even when the composer is
    // off (it then mirrors these via `derivedComposition`).
    @Default(.eventTitleIconFormat) private var eventTitleIconFormat
    @Default(.eventTitleFormat) private var eventTitleFormat
    @Default(.eventTimeFormat) private var eventTimeFormat
    @Default(.statusbarEventTitleLength) private var statusbarEventTitleLength

    // Dropdown composition + per-module toggles.
    @Default(.dropdownModuleOrder) private var dropdownModuleOrder
    @Default(.showGreetingInMenu) private var showGreetingInMenu
    @Default(.showTimelineInMenu) private var showTimelineInMenu
    @Default(.showMeetingControlInMenu) private var showMeetingControlInMenu
    @Default(.showAgendaInMenu) private var showAgendaInMenu
    @Default(.showJoinSectionInMenu) private var showJoinSectionInMenu
    @Default(.showBookmarksInMenu) private var showBookmarksInMenu
    @Default(.greetingName) private var greetingName

    // Dropdown "More options" toggles that live beside this preview — reflected
    // in the mock so toggling them visibly changes the preview.
    @Default(.hideFinishedEventsInMenu) private var hideFinishedEventsInMenu
    @Default(.showRemindersInMenu) private var showRemindersInMenu

    /// The dropdown mock is drawn at the real dropdown width so the sample rows,
    /// summary card, greeting and timeline all share one visual scale.
    private var cardWidth: CGFloat { MeetingSummaryView.preferredWidth }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("preferences_display_preview_menu_bar_label")
                    menuBarStrip.padding(.horizontal, 16)
                }

                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("preferences_display_preview_dropdown_label")
                    dropdownCard.frame(maxWidth: .infinity, alignment: .center)
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
            title: sampleEvents[0].title,
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
    /// composer is off — mirrors `MenuBarComposition.derivedFromLegacy` but reads
    /// the observed keys so the strip re-renders when the classic toggles change.
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
            weekNumberPrefix: "preferences_appearance_menu_bar_week_number_prefix".loco(),
            iconFormat: StatusBarIconFormat(eventTitleIconFormat),
            iconFormatAssetName: eventTitleIconFormat.rawValue,
            iconAssets: .production,
            tokenSeparator: "  ",
            pendingDisplay: .normal,
            tentativeDisplay: .normal
        )
    }

    // MARK: - Dropdown card

    /// The resolved, visible dropdown modules — the exact list the status-bar
    /// controller builds the real NSMenu from, via the shared enabled-set helper.
    private var resolvedModules: [DropdownModule] {
        DropdownCompositionPolicy.resolve(
            order: dropdownModuleOrder,
            enabled: DropdownCompositionPolicy.enabledRawValues(
                greeting: showGreetingInMenu,
                timeline: showTimelineInMenu,
                meeting: showMeetingControlInMenu,
                agenda: showAgendaInMenu,
                join: showJoinSectionInMenu,
                bookmarks: showBookmarksInMenu
            )
        )
    }

    private var dropdownCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(resolvedModules.enumerated()), id: \.element) { pair in
                if pair.offset > 0 { menuSeparator }
                moduleBlock(pair.element)
            }
            // The Preferences footer is pinned, never a module — shown last so the
            // preview matches the real dropdown's safety guarantee.
            menuSeparator
            preferencesFooter
        }
        .padding(.vertical, 6)
        .frame(width: cardWidth)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10))
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    private var menuSeparator: some View {
        Divider().padding(.vertical, 4)
    }

    @ViewBuilder
    private func moduleBlock(_ module: DropdownModule) -> some View {
        switch module {
        case .greeting: greetingBlock
        case .timeline: timelineBlock
        case .meeting: meetingBlock
        case .agenda: agendaBlock
        case .join: joinBlock
        case .bookmarks: bookmarksBlock
        }
    }

    // MARK: Dropdown module mocks

    private var greetingBlock: some View {
        DaySummaryHeaderView(
            greeting: greetingLine,
            summary: "preferences_display_preview_greeting_summary".loco(),
            symbolName: greetingSymbolName
        )
    }

    /// The REAL timeline view, fed sample segments — not a look-alike. This used
    /// to be a hand-drawn strip of coloured capsules, which is why the preview
    /// and the live dropdown visibly disagreed about what a timeline looks like.
    /// Rendering the actual view means the two cannot drift again.
    private var timelineBlock: some View {
        let timeline = DayRelativeTimelineView(
            segments: sampleEvents.enumerated().map { index, event in
                DaySegment(
                    id: String(event.id),
                    start: event.start,
                    end: event.end,
                    color: event.color,
                    isHighlighted: index == 0,
                    title: event.title
                )
            },
            currentDate: Date(),
            timeFormat: Defaults[.timeFormat]
        )
        return timeline
            .frame(width: cardWidth, height: timeline.preferredHeight)
            .allowsHitTesting(false)
    }

    private var meetingBlock: some View {
        MeetingSummaryView(
            presentation: MeetingSummaryPresentation(
                sectionTitle: "status_bar_control_next_meeting".loco(),
                eventTitle: sampleEvents[0].title,
                metadata: [sampleEvents[0].timeRange],
                meetingService: .zoom,
                countdown: "status_bar_event_status_in".loco(sampleEvents[0].countdown)
            ),
            onJoin: nil
        )
        .frame(width: cardWidth)
        .allowsHitTesting(false)
    }

    private var agendaBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            // A finished (past) meeting — shown dimmed/struck when "Hide finished
            // meetings" is off, and removed when it's on, so toggling that setting
            // visibly changes the preview.
            if !hideFinishedEventsInMenu {
                agendaRow(finishedSampleEvent, finished: true)
            }
            ForEach(sampleEvents) { event in
                agendaRow(event, finished: false)
            }
            // A sample reminder row when "Show today's reminders" is on.
            if showRemindersInMenu {
                reminderRow
            }
        }
        .padding(.vertical, 2)
    }

    private func agendaRow(_ event: SampleEvent, finished: Bool) -> some View {
        HStack(spacing: 8) {
            Text(event.startTime)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Circle().fill(event.color).frame(width: 7, height: 7)
            Text(event.title)
                .font(.system(size: MenuStyleConstants.defaultFontSize))
                .foregroundStyle(finished ? Color.secondary : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .frame(width: cardWidth, alignment: .leading)
    }

    /// A checkbox-style reminder row, shown when reminders are enabled in the menu.
    private var reminderRow: some View {
        HStack(spacing: 8) {
            Spacer().frame(width: 76)
            Image(systemName: "circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("preferences_display_preview_sample_reminder".loco())
                .font(.system(size: MenuStyleConstants.defaultFontSize))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .frame(width: cardWidth, alignment: .leading)
    }

    private var joinBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            menuActionRow(symbol: "video.fill", title: "status_bar_quick_action_join_next".loco())
            menuActionRow(symbol: "plus.circle", title: "status_bar_quick_action_create_meeting".loco())
        }
        .padding(.vertical, 2)
    }

    private var bookmarksBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            menuActionRow(symbol: "bookmark.fill", title: sampleEvents[1].title)
            menuActionRow(symbol: "bookmark.fill", title: sampleEvents[2].title)
        }
        .padding(.vertical, 2)
    }

    private var preferencesFooter: some View {
        menuActionRow(
            symbol: "gearshape",
            title: "preferences_menu_builder_dropdown_module_preferences".loco()
        )
    }

    private func menuActionRow(symbol: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: MenuStyleConstants.defaultFontSize))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .frame(width: cardWidth, alignment: .leading)
    }

    // MARK: - Sample data

    /// A representative event with pre-formatted, locale-aware time strings so the
    /// preview reads sensibly regardless of the user's actual calendar.
    private struct SampleEvent: Identifiable {
        let id: Int
        let title: String
        let startTime: String
        let timeRange: String
        let countdown: String
        let color: Color
        /// Real dates as well as the formatted strings, so the preview can feed
        /// the *actual* `DayRelativeTimelineView` rather than a look-alike mock.
        let start: Date
        let end: Date
    }

    private var sampleEvents: [SampleEvent] {
        let now = Date()
        let calendar = Calendar.current
        func at(_ minutes: Int) -> Date {
            calendar.date(byAdding: .minute, value: minutes, to: now) ?? now
        }
        return [
            SampleEvent(
                id: 0,
                title: "preferences_appearance_menu_bar_preview_sample_event".loco(),
                startTime: timeString(at(25)),
                timeRange: "\(timeString(at(25))) – \(timeString(at(55)))",
                countdown: "25m",
                color: .blue,
                start: at(25),
                end: at(55)
            ),
            SampleEvent(
                id: 1,
                title: "preferences_display_preview_sample_event_2".loco(),
                startTime: timeString(at(90)),
                timeRange: "\(timeString(at(90))) – \(timeString(at(150)))",
                countdown: "1h 30m",
                color: .green,
                start: at(90),
                end: at(150)
            ),
            SampleEvent(
                id: 2,
                title: "preferences_display_preview_sample_event_3".loco(),
                startTime: timeString(at(240)),
                timeRange: "\(timeString(at(240))) – \(timeString(at(300)))",
                countdown: "4h",
                color: .orange,
                start: at(240),
                end: at(300)
            )
        ]
    }

    /// A meeting that already ended, used to show the effect of "Hide finished
    /// meetings" (dimmed/struck when shown; removed when the setting is on).
    private var finishedSampleEvent: SampleEvent {
        let now = Date()
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .minute, value: -60, to: now) ?? now
        let end = calendar.date(byAdding: .minute, value: -30, to: now) ?? now
        return SampleEvent(
            id: -1,
            title: "preferences_display_preview_sample_finished".loco(),
            startTime: timeString(start),
            timeRange: "\(timeString(start)) – \(timeString(end))",
            countdown: "",
            color: .gray,
            start: start,
            end: end
        )
    }

    /// Wall-clock time honoring the user's 12/24h preference + locale, matching
    /// how the app formats event times elsewhere.
    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = I18N.instance.locale
        formatter.setLocalizedDateFormatFromTemplate(timeFormat == .military ? "Hmm" : "hmma")
        return formatter.string(from: date)
    }

    // MARK: Greeting

    private var greetingLine: String {
        let name = resolvedGreetingName
        switch DaySummaryPolicy.timeOfDay(now: Date(), calendar: Calendar.current) {
        case .morning: return "menu_greeting_morning_named".loco(name)
        case .afternoon: return "menu_greeting_afternoon_named".loco(name)
        case .evening: return "menu_greeting_evening_named".loco(name)
        }
    }

    private var greetingSymbolName: String {
        switch DaySummaryPolicy.timeOfDay(now: Date(), calendar: Calendar.current) {
        case .morning: return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "moon.stars.fill"
        }
    }

    /// The user's greeting name (first component, matching the real menu), or a
    /// localized sample name — so typing a name in Settings updates the preview.
    private var resolvedGreetingName: String {
        let trimmed = greetingName.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? "preferences_display_preview_greeting_name".loco() : trimmed
        return source.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? source
    }
}

#Preview {
    DisplayPreviewPane().frame(width: 340, height: 620)
}
