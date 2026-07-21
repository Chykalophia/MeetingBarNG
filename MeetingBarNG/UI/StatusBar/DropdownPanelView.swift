//
//  DropdownPanelView.swift
//  MeetingBarNG
//
//  The custom SwiftUI dropdown panel (Phase A of the dropdown modernization).
//  An OPT-IN alternative to the classic `NSMenu` built by `MenuBuilder`: the menu
//  stays the default and is untouched, and this panel only appears when the user
//  turns on `Defaults[.useSwiftUIDropdown]` in Preferences ▸ Display.
//
//  Renders the SAME resolved modules, in the same order, as the real menu —
//  `DropdownCompositionPolicy.resolve(order:enabled:)` fed by the shared
//  `enabledRawValues(...)` helper — from a real `StatusBarMenuState` snapshot, so
//  the panel can never drift from the menu it will eventually replace. Reuses the
//  existing `DaySummaryHeaderView`, `DayRelativeTimelineView` and
//  `MeetingSummaryView` for the top three modules.
//
//  Presentation-only: every side effect (join, create, preferences, quit, …)
//  goes out through an injected `DropdownPanelHandlers` closure, so the view has
//  no dependency on the status-bar controller.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import AppKit
import Defaults
import SwiftUI

/// Everything the panel can *do*, injected by `StatusBarItemController` so the
/// view itself stays free of side effects. `dismiss` is supplied by the window
/// host (`WindowCoordinator.openDropdownPanel`) and closes the panel.
struct DropdownPanelHandlers {
    var joinEvent: @MainActor (MBEvent) -> Void = { _ in }
    var openBookmark: @MainActor (Bookmark) -> Void = { _ in }
    var createMeeting: @MainActor () -> Void = {}
    var refresh: @MainActor () -> Void = {}
    var openPreferences: @MainActor () -> Void = {}
    /// Wired for the Phase B quick-action rows (calendar window / command bar);
    /// the Phase A panel doesn't surface them yet.
    var openCalendar: @MainActor () -> Void = {}
    var openCommandBar: @MainActor () -> Void = {}
    var quit: @MainActor () -> Void = {}
    var dismiss: @MainActor () -> Void = {}
}

struct DropdownPanelView: View {
    let state: StatusBarMenuState
    let handlers: DropdownPanelHandlers
    /// Injected so the panel formats times against the snapshot's moment (and so
    /// previews/tests are deterministic).
    var now: Date = Date()

    /// The stored module order. Read here (rather than passed in) so the panel
    /// resolves its layout through exactly the same policy the controller and the
    /// Display-tab preview use.
    @Default(.dropdownModuleOrder) private var dropdownModuleOrder

    /// Same narrow width as the NSMenu dropdown's hosted rows, so the greeting,
    /// timeline and summary card keep their existing proportions.
    static var preferredWidth: CGFloat { MeetingSummaryView.preferredWidth }

    /// A long day scrolls inside the panel instead of growing past the screen.
    /// `DropdownPanelPlacement` trims this further when the display is short.
    static let maximumHeight: CGFloat = 600

    /// Shared with the window host so the AppKit corner mask matches the
    /// SwiftUI background exactly (no hairline at the corners).
    static let cornerRadius: CGFloat = 10

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleModules.enumerated()), id: \.element) { pair in
                    if pair.offset > 0 { separator }
                    moduleBlock(pair.element)
                }
                // The Preferences footer is pinned, never a module, so the user
                // can't hide Settings/Quit — same guarantee as the real menu.
                separator
                footerBlock
            }
            .padding(.vertical, 6)
            .frame(width: Self.preferredWidth, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: Self.preferredWidth)
        .frame(maxHeight: Self.maximumHeight)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10))
        )
    }

    // MARK: - Composition

    /// The resolved, visible modules — the exact list the status-bar controller
    /// builds the real NSMenu from — minus the ones with nothing to render (so
    /// the panel never shows a stray separator).
    private var visibleModules: [DropdownModule] {
        DropdownCompositionPolicy.resolve(
            order: dropdownModuleOrder,
            enabled: DropdownCompositionPolicy.enabledRawValues(
                greeting: state.showGreetingHeader,
                timeline: state.menu.showTimelineInMenu,
                meeting: state.menu.showMeetingControlInMenu,
                agenda: state.menu.showAgendaInMenu,
                join: state.menu.showJoinSectionInMenu,
                bookmarks: state.menu.showBookmarksInMenu
            )
        )
        .filter(hasContent)
    }

    /// Mirrors the controller's per-module gates in `updateMenu()`.
    private func hasContent(_ module: DropdownModule) -> Bool {
        switch module {
        case .greeting: state.shouldShowGreetingHeader
        case .timeline: state.shouldShowTimeline
        case .meeting: true
        case .agenda: state.hasSelectedCalendars
        case .join: true
        case .bookmarks: !state.meetings.bookmarks.isEmpty
        }
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

    private var separator: some View {
        Divider().padding(.vertical, 4)
    }

    // MARK: - Greeting

    @ViewBuilder
    private var greetingBlock: some View {
        if let summary = state.daySummary {
            DaySummaryHeaderView(
                greeting: greetingLine(summary.timeOfDay),
                summary: daySummaryLine(summary),
                symbolName: greetingSymbolName(summary.timeOfDay)
            )
        }
    }

    // Greeting copy mirrors `MenuBuilder`'s (its formatters are private); the
    // structured `DaySummary` itself comes from the shared `DaySummaryPolicy`.
    private func greetingLine(_ timeOfDay: GreetingTimeOfDay) -> String {
        let name = state.greetingName
        let key: String
        switch timeOfDay {
        case .morning:
            key = name == nil ? "menu_greeting_morning" : "menu_greeting_morning_named"
        case .afternoon:
            key = name == nil ? "menu_greeting_afternoon" : "menu_greeting_afternoon_named"
        case .evening:
            key = name == nil ? "menu_greeting_evening" : "menu_greeting_evening_named"
        }
        return name.map { key.loco($0) } ?? key.loco()
    }

    private func greetingSymbolName(_ timeOfDay: GreetingTimeOfDay) -> String {
        switch timeOfDay {
        case .morning: "sunrise.fill"
        case .afternoon: "sun.max.fill"
        case .evening: "moon.stars.fill"
        }
    }

    private func daySummaryLine(_ summary: DaySummary) -> String {
        let countText: String
        switch summary.eventCount {
        case 0: countText = "menu_day_summary_no_events".loco()
        case 1: countText = "menu_day_summary_event_count_one".loco(summary.eventCount)
        default: countText = "menu_day_summary_event_count_other".loco(summary.eventCount)
        }
        let freeText = "menu_day_summary_focus_time".loco(formattedFreeTime(summary.freeMinutes))
        return "\(countText) · \(freeText)"
    }

    private func formattedFreeTime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0, mins > 0 { return "\(hours)h \(mins)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(mins)m"
    }

    // MARK: - Timeline

    private var timelineBlock: some View {
        let timeline = DayRelativeTimelineView(
            segments: timelineSegments,
            currentDate: now,
            timeFormat: state.timeFormat
        )
        return timeline
            .frame(width: Self.preferredWidth, height: timeline.preferredHeight)
    }

    private var timelineSegments: [DaySegment] {
        let startOfDay = Calendar.current.startOfDay(for: now)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? now
        let highlightedEventID = state.nextEvent?.id
        return visibleEvents(state.todayEvents).map { event in
            DaySegment(
                id: event.id,
                start: max(event.startDate, startOfDay),
                end: min(event.endDate, endOfDay),
                color: Color(nsColor: event.calendar.color),
                isHighlighted: event.id == highlightedEventID,
                title: event.title
            )
        }
    }

    // MARK: - Meeting control

    @ViewBuilder
    private var meetingBlock: some View {
        if let event = state.nextEvent {
            let presentation = meetingSummaryPresentation(for: event)
            MeetingSummaryView(
                presentation: presentation,
                providerIcon: getIconForMeetingService(presentation.meetingService),
                onJoin: event.meetingLink == nil
                    ? nil
                    : { handlers.joinEvent(event); handlers.dismiss() }
            )
            .frame(width: Self.preferredWidth)
        } else {
            emptyStateBlock
        }
    }

    /// Reuses `MenuBuilder`'s presentation mapping so the card's copy (section
    /// title, metadata, countdown) is identical in both dropdowns. The builder's
    /// `target` is only used for NSMenuItem actions, which this path never makes.
    private func meetingSummaryPresentation(for event: MBEvent) -> MeetingSummaryPresentation {
        MenuBuilder(
            target: NSNull(),
            state: state,
            isFantasticalInstalled: false,
            now: now
        )
        .meetingSummaryPresentation(for: event)
    }

    /// The honest reason there is no meeting to show, plus the one action that
    /// can fix it — the same mapping `MenuBuilder.buildEmptyMeetingControlSection`
    /// uses, with the auth/permission repairs routed to Preferences.
    @ViewBuilder
    private var emptyStateBlock: some View {
        let reason = state.emptyStateReason ?? .noUpcomingMeetings
        VStack(alignment: .leading, spacing: 2) {
            Text(emptyStateTitle(reason))
                .font(.system(size: MenuStyleConstants.defaultFontSize, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            actionRow(
                symbol: emptyStateSymbol(reason),
                title: emptyStateActionTitle(reason),
                action: emptyStateIsRepairable(reason) ? handlers.openPreferences : handlers.refresh
            )
        }
    }

    private func emptyStateTitle(_ reason: StatusBarEmptyStateReason) -> String {
        switch reason {
        case .authRequired: "status_bar_control_auth_required".loco()
        case .permissionRequired: "status_bar_control_permission_required".loco()
        case .noCalendarsAvailable: "status_bar_control_no_calendars_available".loco()
        case .noCalendarsSelected: "status_bar_control_no_calendars".loco()
        case .refreshFailed: "status_bar_control_refresh_failed".loco()
        case .noUpcomingMeetings: "status_bar_control_no_upcoming".loco()
        }
    }

    private func emptyStateActionTitle(_ reason: StatusBarEmptyStateReason) -> String {
        switch reason {
        case .authRequired, .permissionRequired: "status_bar_quick_action_preferences".loco()
        case .noCalendarsAvailable: "status_bar_control_open_calendar_preferences".loco()
        case .noCalendarsSelected: "status_bar_control_select_calendars".loco()
        case .refreshFailed, .noUpcomingMeetings: "status_bar_section_refresh_sources".loco()
        }
    }

    private func emptyStateSymbol(_ reason: StatusBarEmptyStateReason) -> String {
        emptyStateIsRepairable(reason) ? "gearshape" : "arrow.clockwise"
    }

    /// Reasons a Preferences visit can fix (connect / grant / select calendars);
    /// the rest are transient and offer a refresh instead.
    private func emptyStateIsRepairable(_ reason: StatusBarEmptyStateReason) -> Bool {
        switch reason {
        case .authRequired, .permissionRequired, .noCalendarsAvailable, .noCalendarsSelected: true
        case .refreshFailed, .noUpcomingMeetings: false
        }
    }

    // MARK: - Agenda

    private var agendaBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            dateSection(
                title: "status_bar_section_today".loco(),
                date: now,
                events: visibleEvents(state.todayEvents)
            )
            remindersRows
            if state.events.showEventsForPeriod == .today_n_tomorrow {
                separator
                dateSection(
                    title: "status_bar_section_tomorrow".loco(),
                    date: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now,
                    events: visibleEvents(state.tomorrowEvents)
                )
            }
        }
    }

    @ViewBuilder
    private func dateSection(title: String, date: Date, events: [MBEvent]) -> some View {
        sectionHeader("\(title) (\(sectionDateText(date)))")
        if events.isEmpty {
            Text("status_bar_section_date_nothing".loco(title.lowercased()))
                .font(.system(size: MenuStyleConstants.defaultFontSize))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
        }
        ForEach(events, id: \.id) { event in
            eventRow(event)
        }
    }

    private func eventRow(_ event: MBEvent) -> some View {
        let isFinished = event.endDate < now
        let isRunning = event.startDate <= now && event.endDate > now
        let canJoin = event.meetingLink != nil
        return PanelRow(action: canJoin ? perform { handlers.joinEvent(event) } : nil) {
            HStack(spacing: 8) {
                Text(eventStartText(event))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 66, alignment: .leading)
                Circle()
                    .fill(Color(nsColor: event.calendar.color))
                    .frame(width: 7, height: 7)
                Text(event.title.isEmpty ? "status_bar_no_title".loco() : event.title)
                    .font(.system(
                        size: MenuStyleConstants.defaultFontSize,
                        weight: isRunning ? .semibold : .regular
                    ))
                    .foregroundStyle(isFinished ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if canJoin {
                    Image(systemName: "video.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Today's reminders, display-only in Phase A (complete / snooze / open stay
    /// on the NSMenu path until Phase B brings per-row actions to the panel).
    @ViewBuilder
    private var remindersRows: some View {
        if !state.todayReminders.isEmpty {
            sectionHeader("status_bar_section_reminders".loco())
            ForEach(state.todayReminders, id: \.id) { reminder in
                HStack(spacing: 8) {
                    Text(reminderTimeText(reminder))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 66, alignment: .leading)
                    Image(systemName: reminder.isCompleted ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(reminder.title.isEmpty ? "status_bar_no_title".loco() : reminder.title)
                        .font(.system(size: MenuStyleConstants.defaultFontSize))
                        .foregroundStyle(reminder.isOverdue ? Color.red : Color.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Join

    @ViewBuilder
    private var joinBlock: some View {
        if let nextEvent = state.nextEvent, nextEvent.meetingLink != nil {
            actionRow(
                symbol: "video.fill",
                title: nextEvent.startDate < now
                    ? "status_bar_section_join_current_meeting".loco()
                    : "status_bar_section_join_next_meeting".loco(),
                action: { handlers.joinEvent(nextEvent) }
            )
        }
        actionRow(
            symbol: "plus.circle",
            title: "status_bar_section_join_create_meeting".loco(),
            action: handlers.createMeeting
        )
    }

    // MARK: - Bookmarks

    private var bookmarksBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("status_bar_section_bookmarks_title".loco())
            ForEach(state.meetings.bookmarks, id: \.self) { bookmark in
                actionRow(
                    symbol: "bookmark.fill",
                    title: bookmark.name,
                    action: { handlers.openBookmark(bookmark) }
                )
            }
        }
    }

    // MARK: - Pinned footer

    private var footerBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionRow(
                symbol: "gearshape",
                title: "\("status_bar_preferences".loco())…",
                action: handlers.openPreferences
            )
            actionRow(
                symbol: "power",
                title: "status_bar_quit".loco(),
                action: handlers.quit
            )
        }
    }

    // MARK: - Shared row chrome

    private func actionRow(
        symbol: String,
        title: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        PanelRow(action: perform(action)) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: MenuStyleConstants.defaultFontSize))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: MenuStyleConstants.defaultFontSize - 2, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }

    /// Wraps a handler so running it also closes the panel (a menu item's
    /// click-then-dismiss behavior).
    private func perform(_ action: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        let dismiss = handlers.dismiss
        return {
            action()
            dismiss()
        }
    }

    // MARK: - Formatting

    private func visibleEvents(_ events: [MBEvent]) -> [MBEvent] {
        events
            .filter {
                !state.menu.hideFinishedEventsInMenu
                    || EventListWindow.isVisible(endDate: $0.endDate, now: now)
            }
            .sorted { $0.startDate < $1.startDate }
    }

    private func eventStartText(_ event: MBEvent) -> String {
        event.isAllDay
            ? "status_bar_event_start_time_all_day".loco()
            : clockText(event.startDate)
    }

    private func reminderTimeText(_ reminder: MBReminder) -> String {
        guard reminder.hasTime, let due = reminder.dueDate else { return "" }
        return clockText(due)
    }

    private func clockText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = I18N.instance.locale
        formatter.dateFormat = state.timeFormat == .am_pm ? "h:mm a" : "HH:mm"
        return formatter.string(from: date)
    }

    private func sectionDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = I18N.instance.locale
        formatter.dateFormat = "E, d MMM"
        return formatter.string(from: date)
    }
}

// MARK: - Row

/// One interactive row: hover highlight + pointing-hand cursor when it has an
/// action, plain layout when it doesn't. The hover state is the whole point of
/// the custom panel — a plain NSMenuItem can't do it.
private struct PanelRow<Content: View>: View {
    let action: (@MainActor () -> Void)?
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    var body: some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered && action != nil
                        ? Color.accentColor.opacity(0.18)
                        : Color.clear)
            )
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            // Scoped pointer style (macOS 15+): unlike NSCursor.push/pop it can't
            // strand a pointing-hand cursor when the panel closes mid-hover.
            // https://developer.apple.com/documentation/swiftui/view/pointerstyle(_:)
            .pointerStyle(action == nil ? nil : .link)
            .onHover { hovering in
                guard action != nil else { return }
                withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
            }
            .onTapGesture { action?() }
    }
}

#Preview {
    DropdownPanelView(state: StatusBarMenuState(), handlers: DropdownPanelHandlers())
}
