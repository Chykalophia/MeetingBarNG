//
//  DropdownPanelView.swift
//  MeetingBarNG
//
//  The custom SwiftUI dropdown panel (Phases A + B of the dropdown
//  modernization). An OPT-IN alternative to the classic `NSMenu` built by
//  `MenuBuilder`: the menu stays the default and is untouched, and this panel
//  only appears when the user turns on `Defaults[.useSwiftUIDropdown]` in
//  Preferences ▸ Display.
//
//  Renders the SAME resolved modules, in the same order, as the real menu —
//  `DropdownCompositionPolicy.resolve(order:enabled:)` fed by the shared
//  `enabledRawValues(...)` helper — from a real `StatusBarMenuState` snapshot, so
//  the panel can never drift from the menu it will eventually replace. Reuses the
//  existing `DaySummaryHeaderView`, `DayRelativeTimelineView` and
//  `MeetingSummaryView` for the top three modules.
//
//  Phase B brings it to functional parity with the menu, and past it where
//  SwiftUI can do things an NSMenuItem cannot:
//    • a right-click `.contextMenu` on every event row and on the meeting card,
//      carrying the whole NSMenu action set (join / copy link / edit / delete /
//      email attendees / dismiss / prep links / alternate meeting links);
//    • a hover-revealed trailing Join affordance whose space is always reserved,
//      so the row never shifts;
//    • an inline detail disclosure (time range, location, organizer, attendees,
//      notes — each click-to-copy) replacing the NSMenu detail submenu, its
//      chevron revealed on hover/selection so resting rows stay clean;
//    • functional reminder rows (checkbox complete + snooze + open in Reminders);
//    • keyboard navigation over the flattened interactive rows, ordered by the
//      hostless, unit-tested `DropdownPanelNavigation`.
//
//  Presentation-only: every side effect (join, copy, edit, delete, quit, …) goes
//  out through an injected `DropdownPanelHandlers` closure, so the view has no
//  dependency on the status-bar controller.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import AppKit
import Defaults
import SwiftUI

/// Everything the panel can *do*, injected by `StatusBarItemController` so the
/// view itself stays free of side effects. `dismiss` is supplied by the window
/// host (`WindowCoordinator.openDropdownPanel`) and closes the panel.
///
/// Phase B: every per-event / per-reminder action the NSMenu offers is here too,
/// each forwarding to the same controller code path the menu item's `@objc`
/// action runs, so the two dropdowns can never diverge in behavior.
struct DropdownPanelHandlers {
    var joinEvent: @MainActor (MBEvent) -> Void = { _ in }
    var openBookmark: @MainActor (Bookmark) -> Void = { _ in }
    var createMeeting: @MainActor () -> Void = {}
    var refresh: @MainActor () -> Void = {}
    var openPreferences: @MainActor () -> Void = {}
    /// Wired for the Phase B quick-action rows (calendar window / command bar);
    /// the panel doesn't surface them yet.
    var openCalendar: @MainActor () -> Void = {}
    var openCommandBar: @MainActor () -> Void = {}
    var openChangelog: @MainActor () -> Void = {}
    var quit: @MainActor () -> Void = {}
    var dismiss: @MainActor () -> Void = {}

    // MARK: - Per-event actions (NSMenu parity)

    var editEvent: @MainActor (MBEvent) -> Void = { _ in }
    /// Routes to the controller's destructive path: an NSAlert confirmation
    /// (including the recurring this-event / this-and-future choice) BEFORE the
    /// EventKit write.
    var deleteEvent: @MainActor (MBEvent) -> Void = { _ in }
    /// Click-to-copy for a detail string (location, organizer, attendee, notes).
    var copyText: @MainActor (String) -> Void = { _ in }
    var copyMeetingLink: @MainActor (MBEvent) -> Void = { _ in }
    /// Opens a reference URL in the default browser — meeting-prep links and
    /// alternate meeting links.
    var openURL: @MainActor (URL) -> Void = { _ in }
    var emailAttendees: @MainActor (MBEvent) -> Void = { _ in }
    var dismissEvent: @MainActor (MBEvent) -> Void = { _ in }
    var undismissEvent: @MainActor (MBEvent) -> Void = { _ in }

    // MARK: - Per-reminder actions (NSMenu parity)

    var completeReminder: @MainActor (MBReminder) -> Void = { _ in }
    var snoozeReminder: @MainActor (MBReminder, ReminderSnoozeOption) -> Void = { _, _ in }
    var openReminderInApp: @MainActor (MBReminder) -> Void = { _ in }
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

    /// Index into `navigationRows` of the keyboard-selected row, or `nil` when
    /// nothing is selected yet (the state the panel opens in).
    @State private var selectionIndex: Int?
    /// Event ids whose inline detail disclosure is expanded.
    @State private var expandedEventIDs: Set<String> = []
    /// Drives the panel's key focus so Up/Down/Return reach `onMoveCommand` /
    /// `onKeyPress`. The window itself already becomes key on open.
    @FocusState private var isPanelFocused: Bool

    /// Same narrow width as the NSMenu dropdown's hosted rows, so the greeting,
    /// timeline and summary card keep their existing proportions.
    static var preferredWidth: CGFloat { MeetingSummaryView.preferredWidth }

    /// A long day scrolls inside the panel instead of growing past the screen.
    /// `DropdownPanelPlacement` trims this further when the display is short.
    static let maximumHeight: CGFloat = 600

    /// Shared with the window host so the AppKit corner mask matches the
    /// SwiftUI background exactly (no hairline at the corners).
    static let cornerRadius: CGFloat = 10

    /// Fixed width of the trailing affordance slot on an event row. Reserved
    /// whether or not the row is hovered, so revealing the Join button never
    /// shifts the row's layout.
    private static let trailingAffordanceWidth: CGFloat = 48

    var body: some View {
        ScrollViewReader { proxy in
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
            .onChange(of: selectionIndex) { _, _ in
                guard let selectedRow else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(selectedRow, anchor: .center)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        // A menu never shows a scrollbar. The panel scrolls only when a very
        // long day overflows `maximumHeight`, and even then the indicator stays
        // hidden so it reads as a menu rather than a scroll view.
        .scrollIndicators(.hidden)
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
        // Keyboard-first: the panel takes key focus on open (the window is made
        // key by the host), then Up/Down walk the flattened interactive rows and
        // Return runs the selected row's primary action. Escape is handled by
        // `DropdownPanelWindow`.
        .focusable()
        .focusEffectDisabled()
        .focused($isPanelFocused)
        .onAppear { isPanelFocused = true }
        .onMoveCommand { direction in
            switch direction {
            case .up: moveSelection(.up)
            case .down: moveSelection(.down)
            default: break
            }
        }
        // macOS 14+ key-press reporting; the app's floor is macOS 15.
        // https://developer.apple.com/documentation/swiftui/view/onkeypress(_:action:)
        .onKeyPress(.return) { activateSelection() ? .handled : .ignored }
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

    // MARK: - Keyboard navigation

    /// What the panel is rendering, described hostlessly so the row order — and
    /// therefore the keyboard behavior — is unit-tested in
    /// `DropdownPanelNavigationTests` rather than only in the UI.
    private var navigationContent: DropdownPanelContent {
        DropdownPanelContent(
            modules: visibleModules,
            meetingEventID: state.nextEvent?.id,
            todayEventIDs: visibleEvents(state.todayEvents).map(\.id),
            reminderIDs: state.todayReminders.map(\.id),
            tomorrowEventIDs: showsTomorrowSection
                ? visibleEvents(state.tomorrowEvents).map(\.id)
                : [],
            joinNextEventID: joinSectionEvent?.id,
            bookmarkCount: state.meetings.bookmarks.count,
            showsWhatsNew: showsWhatsNew
        )
    }

    private var navigationRows: [DropdownPanelRow] {
        DropdownPanelNavigation.interactiveRows(for: navigationContent)
    }

    private var selectedRow: DropdownPanelRow? {
        guard let selectionIndex, navigationRows.indices.contains(selectionIndex) else {
            return nil
        }
        return navigationRows[selectionIndex]
    }

    private func moveSelection(_ direction: DropdownPanelMoveDirection) {
        selectionIndex = DropdownPanelNavigation.next(
            from: selectionIndex,
            direction: direction,
            count: navigationRows.count
        )
    }

    /// Runs the selected row's primary action. Returns `false` when nothing is
    /// selected, so the key press falls through to AppKit.
    private func activateSelection() -> Bool {
        guard let selectedRow else { return false }
        switch selectedRow {
        case .meetingSummary(let id), .event(let id):
            guard let event = event(withID: id) else { return false }
            primaryAction(for: event)
        case .emptyStateAction:
            emptyStateAction()
        case .reminder(let id):
            guard let reminder = state.todayReminders.first(where: { $0.id == id }) else {
                return false
            }
            perform { handlers.completeReminder(reminder) }()
        case .joinNext(let id):
            guard let event = event(withID: id) else { return false }
            perform { handlers.joinEvent(event) }()
        case .createMeeting:
            perform(handlers.createMeeting)()
        case .bookmark(let index):
            guard state.meetings.bookmarks.indices.contains(index) else { return false }
            let bookmark = state.meetings.bookmarks[index]
            perform { handlers.openBookmark(bookmark) }()
        case .whatsNew:
            perform(handlers.openChangelog)()
        case .preferences:
            perform(handlers.openPreferences)()
        case .quit:
            perform(handlers.quit)()
        }
        return true
    }

    private func event(withID id: String) -> MBEvent? {
        if let next = state.nextEvent, next.id == id { return next }
        return (state.todayEvents + state.tomorrowEvents).first { $0.id == id }
    }

    private func isSelected(_ row: DropdownPanelRow) -> Bool {
        selectedRow == row
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
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected(.meetingSummary(event.id))
                        ? Color.accentColor.opacity(0.18)
                        : Color.clear)
                    .padding(.horizontal, 6)
            )
            // Right-click parity: the whole per-event action set the NSMenu puts
            // behind the card's "Actions" submenu.
            .contextMenu { eventContextMenu(event) }
            .id(DropdownPanelRow.meetingSummary(event.id))
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
                row: .emptyStateAction,
                action: emptyStateAction
            )
        }
    }

    private func emptyStateAction() {
        let reason = state.emptyStateReason ?? .noUpcomingMeetings
        if emptyStateIsRepairable(reason) {
            perform(handlers.openPreferences)()
        } else {
            perform(handlers.refresh)()
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

    private var showsTomorrowSection: Bool {
        state.events.showEventsForPeriod == .today_n_tomorrow
    }

    private var agendaBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            dateSection(
                title: "status_bar_section_today".loco(),
                date: now,
                events: visibleEvents(state.todayEvents)
            )
            remindersRows
            if showsTomorrowSection {
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

    // MARK: - Event row

    private func eventRow(_ event: MBEvent) -> some View {
        let row = DropdownPanelRow.event(event.id)
        return VStack(alignment: .leading, spacing: 0) {
            PanelRow(isSelected: isSelected(row), action: { primaryAction(for: event) }) { hovering in
                eventRowContent(event, isHovered: hovering)
            }
            if isExpanded(event) {
                eventDetails(event)
            }
        }
        // Right-click gives full NSMenu parity on any row.
        .contextMenu { eventContextMenu(event) }
        .id(row)
    }

    private func eventRowContent(_ event: MBEvent, isHovered: Bool) -> some View {
        let isFinished = event.endDate < now
        let isRunning = event.startDate <= now && event.endDate > now
        return HStack(spacing: 8) {
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
            trailingAffordance(event, isHovered: isHovered)
            disclosureChevron(event, isHovered: isHovered)
        }
    }

    /// The hover-revealed Join button. The slot is a fixed width and the two
    /// states are stacked, so revealing the button on hover never re-lays-out the
    /// row — the thing a plain NSMenuItem could never do.
    @ViewBuilder
    private func trailingAffordance(_ event: MBEvent, isHovered: Bool) -> some View {
        if event.meetingLink != nil {
            let revealed = isHovered || isSelected(.event(event.id))
            ZStack(alignment: .trailing) {
                Image(systemName: "video.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .opacity(revealed ? 0 : 1)
                Text("notifications_meetingbar_join_event_action".loco())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor))
                    .opacity(revealed ? 1 : 0)
                    .contentShape(Capsule())
                    .onTapGesture(perform: perform { handlers.joinEvent(event) })
            }
            .frame(width: Self.trailingAffordanceWidth, alignment: .trailing)
            .animation(.easeOut(duration: 0.12), value: revealed)
        }
    }

    /// Inline detail disclosure. Deliberately NOT gated on `showEventDetails`:
    /// that preference exists because the NSMenu had to build a *nested submenu*
    /// per event, which was expensive and cluttered whether or not you opened it.
    /// Expansion here is user-initiated and costs nothing while collapsed, so the
    /// affordance is always available — it just stays invisible until the row is
    /// hovered or keyboard-selected, keeping the resting list clean. The slot is a
    /// fixed size and the chevron fades, so revealing it never re-lays-out the row.
    private func disclosureChevron(_ event: MBEvent, isHovered: Bool) -> some View {
        let expanded = isExpanded(event)
        let revealed = isHovered || isSelected(.event(event.id)) || expanded
        return Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .opacity(revealed ? 1 : 0)
            .frame(width: 14, height: 14)
            .contentShape(Rectangle())
            .onTapGesture { toggleExpansion(event) }
            .help(expanded
                ? "dropdown_panel_hide_details".loco()
                : "dropdown_panel_show_details".loco())
            .animation(.easeOut(duration: 0.12), value: revealed)
    }

    private func isExpanded(_ event: MBEvent) -> Bool {
        expandedEventIDs.contains(event.id)
    }

    private func toggleExpansion(_ event: MBEvent) {
        withAnimation(.easeOut(duration: 0.12)) {
            if expandedEventIDs.contains(event.id) {
                expandedEventIDs.remove(event.id)
            } else {
                expandedEventIDs.insert(event.id)
            }
        }
    }

    /// A row's primary action: join when there is a meeting link, otherwise open
    /// the inline details.
    private func primaryAction(for event: MBEvent) {
        if event.meetingLink != nil {
            perform { handlers.joinEvent(event) }()
        } else {
            toggleExpansion(event)
        }
    }

    // MARK: - Inline event details (replaces the NSMenu detail submenu)

    @ViewBuilder
    private func eventDetails(_ event: MBEvent) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            detailRow(symbol: "clock", text: timeRangeText(event))
            if let location = event.location, !location.isEmpty {
                detailRow(symbol: "mappin.and.ellipse", text: location)
            }
            if let organizer = event.organizer {
                detailRow(
                    symbol: "person.crop.circle",
                    text: "status_bar_submenu_organizer_title".loco(organizer.name),
                    copyValue: organizer.email ?? organizer.name
                )
            }
            attendeeDetails(event)
            notesDetail(event)
        }
        .padding(.leading, 32)
        .padding(.trailing, 16)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func attendeeDetails(_ event: MBEvent) -> some View {
        if !event.attendees.isEmpty {
            let attendees = event.attendees.sorted { $0.status.rawValue < $1.status.rawValue }
            detailLabel("status_bar_submenu_attendees_title".loco(attendees.count))
            ForEach(attendees, id: \.self) { attendee in
                detailRow(
                    symbol: nil,
                    text: attendeeTitle(attendee),
                    copyValue: attendee.email ?? attendee.name
                )
            }
        }
    }

    private func attendeeTitle(_ attendee: MBEventAttendee) -> String {
        let name = attendee.isCurrentUser
            ? "status_bar_submenu_attendees_you".loco(attendee.name)
            : attendee.name
        switch attendee.status {
        case .tentative:
            return name + "status_bar_submenu_attendees_status_tentative".loco()
        case .pending:
            return name + "status_bar_submenu_attendees_status_unknown".loco()
        default:
            return name
        }
    }

    @ViewBuilder
    private func notesDetail(_ event: MBEvent) -> some View {
        if let rawNotes = event.notes {
            let notes = cleanUpNotes(rawNotes).trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty {
                detailLabel(sectionLabel("status_bar_submenu_notes_title"))
                detailRow(symbol: nil, text: notes, lineLimit: 6)
            }
        }
    }

    private func detailLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: MenuStyleConstants.defaultFontSize - 2, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 3)
    }

    /// One click-to-copy detail line. Copying deliberately leaves the panel open
    /// (an NSMenu had to close; this doesn't), so several details can be grabbed
    /// in a row.
    private func detailRow(
        symbol: String?,
        text: String,
        copyValue: String? = nil,
        lineLimit: Int = 2
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)
            }
            Text(text)
                .font(.system(size: MenuStyleConstants.defaultFontSize - 1))
                .foregroundStyle(.secondary)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { handlers.copyText(copyValue ?? text) }
        .help("status_bar_submenu_click_to_copy".loco())
    }

    private func timeRangeText(_ event: MBEvent) -> String {
        guard !event.isAllDay else { return "status_bar_event_start_time_all_day".loco() }
        let minutes = String(Int(event.endDate.timeIntervalSince(event.startDate) / 60))
        return "status_bar_submenu_duration_all_day".loco(
            clockText(event.startDate),
            clockText(event.endDate),
            minutes
        )
    }

    // MARK: - Per-event context menu (full NSMenu parity)

    @ViewBuilder
    private func eventContextMenu(_ event: MBEvent) -> some View {
        if event.meetingLink != nil {
            Button("notifications_meetingbar_join_event_action".loco()) {
                perform { handlers.joinEvent(event) }()
            }
            Button("status_bar_submenu_copy_meeting_link".loco()) {
                perform { handlers.copyMeetingLink(event) }()
            }
        }
        alternateLinksMenu(event)
        prepLinksMenu(event)
        Divider()
        Button("status_bar_submenu_email_attendees".loco()) {
            perform { handlers.emailAttendees(event) }()
        }
        if isDismissed(event) {
            Button("status_bar_submenu_undismiss_meeting".loco()) {
                perform { handlers.undismissEvent(event) }()
            }
        } else {
            Button("status_bar_submenu_dismiss_meeting".loco()) {
                perform { handlers.dismissEvent(event) }()
            }
        }
        // In-app Edit / Delete (Dot parity). EventKit only, exactly like the
        // NSMenu: the writer targets EKEventStore, so a Google event can't resolve.
        if state.activeProvider == .macOSEventKit {
            Divider()
            Button("status_bar_submenu_edit_event".loco()) {
                dismissThen { handlers.editEvent(event) }()
            }
            Button("status_bar_submenu_delete_event".loco(), role: .destructive) {
                // The panel goes away BEFORE the confirmation alert: it floats at
                // the pop-up-menu level and would otherwise sit over the sheet.
                dismissThen { handlers.deleteEvent(event) }()
            }
        }
    }

    @ViewBuilder
    private func alternateLinksMenu(_ event: MBEvent) -> some View {
        if !event.alternateMeetingLinkCandidates.isEmpty {
            Menu("status_bar_join_with_other_link".loco()) {
                ForEach(event.alternateMeetingLinkCandidates, id: \.self) { candidate in
                    Button(alternateMeetingLinkTitle(candidate)) {
                        perform { handlers.openURL(candidate.url) }()
                    }
                }
            }
        }
    }

    private func alternateMeetingLinkTitle(_ candidate: MeetingLinkCandidate) -> String {
        let service = candidate.service?.localizedValue ?? "constants_meeting_service_other".loco()
        guard let host = candidate.url.host else { return service }
        return "\(service) - \(host)"
    }

    /// Meeting-prep links extracted from the invite, using the same pure
    /// `MeetingPrepLinks` extractor and the same `showMeetingPrepLinks` gate the
    /// NSMenu uses.
    @ViewBuilder
    private func prepLinksMenu(_ event: MBEvent) -> some View {
        let links = prepLinks(for: event)
        if !links.isEmpty {
            Menu(sectionLabel("status_bar_submenu_prep_links_title")) {
                ForEach(links, id: \.url) { link in
                    if let url = URL(string: link.url) {
                        Button(link.displayTitle) {
                            perform { handlers.openURL(url) }()
                        }
                    }
                }
            }
        }
    }

    private func prepLinks(for event: MBEvent) -> [PrepLink] {
        guard state.menu.showMeetingPrepLinks else { return [] }
        return MeetingPrepLinks.extract(
            notes: event.notes,
            location: event.location,
            excluding: [event.meetingLink?.url, event.url].compactMap { $0?.absoluteString }
        )
    }

    private func isDismissed(_ event: MBEvent) -> Bool {
        state.events.dismissedEvents.contains { $0.id == event.id }
    }

    // MARK: - Reminders

    /// Today's reminders. Phase B makes them functional: the checkbox circle (and
    /// the row itself) completes, and a right-click offers Complete / Snooze /
    /// Open in Reminders — the same actions as the NSMenu's reminder submenu.
    @ViewBuilder
    private var remindersRows: some View {
        if !state.todayReminders.isEmpty {
            sectionHeader("status_bar_section_reminders".loco())
            ForEach(state.todayReminders, id: \.id) { reminder in
                reminderRow(reminder)
            }
        }
    }

    private func reminderRow(_ reminder: MBReminder) -> some View {
        let row = DropdownPanelRow.reminder(reminder.id)
        return PanelRow(
            isSelected: isSelected(row),
            action: perform { handlers.completeReminder(reminder) }
        ) { _ in
            HStack(spacing: 8) {
                Text(reminderTimeText(reminder))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 66, alignment: .leading)
                Image(systemName: reminder.isCompleted ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: perform { handlers.completeReminder(reminder) })
                    .help("status_bar_reminders_complete".loco())
                Text(reminder.title.isEmpty ? "status_bar_no_title".loco() : reminder.title)
                    .font(.system(size: MenuStyleConstants.defaultFontSize))
                    .foregroundStyle(reminder.isOverdue ? Color.red : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .contextMenu { reminderContextMenu(reminder) }
        .id(row)
    }

    @ViewBuilder
    private func reminderContextMenu(_ reminder: MBReminder) -> some View {
        Button("status_bar_reminders_complete".loco()) {
            perform { handlers.completeReminder(reminder) }()
        }
        Menu("status_bar_reminders_snooze".loco()) {
            ForEach(ReminderSnoozeOption.allCases, id: \.rawValue) { option in
                Button(reminderSnoozeOptionTitle(option)) {
                    perform { handlers.snoozeReminder(reminder, option) }()
                }
            }
        }
        Divider()
        Button("status_bar_reminders_open_in_reminders".loco()) {
            dismissThen { handlers.openReminderInApp(reminder) }()
        }
    }

    private func reminderSnoozeOptionTitle(_ option: ReminderSnoozeOption) -> String {
        switch option {
        case .laterToday: "status_bar_reminders_snooze_later_today".loco()
        case .thisEvening: "status_bar_reminders_snooze_this_evening".loco()
        case .tomorrow: "status_bar_reminders_snooze_tomorrow".loco()
        }
    }

    // MARK: - Join

    /// The event the join module's "Join …" row acts on, when it renders one.
    private var joinSectionEvent: MBEvent? {
        guard let nextEvent = state.nextEvent, nextEvent.meetingLink != nil else { return nil }
        return nextEvent
    }

    @ViewBuilder
    private var joinBlock: some View {
        if let nextEvent = joinSectionEvent {
            actionRow(
                symbol: "video.fill",
                title: nextEvent.startDate < now
                    ? "status_bar_section_join_current_meeting".loco()
                    : "status_bar_section_join_next_meeting".loco(),
                row: .joinNext(nextEvent.id),
                action: { perform { handlers.joinEvent(nextEvent) }() }
            )
        }
        actionRow(
            symbol: "plus.circle",
            title: "status_bar_section_join_create_meeting".loco(),
            row: .createMeeting,
            action: perform(handlers.createMeeting)
        )
    }

    // MARK: - Bookmarks

    private var bookmarksBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("status_bar_section_bookmarks_title".loco())
            ForEach(Array(state.meetings.bookmarks.enumerated()), id: \.element) { index, bookmark in
                actionRow(
                    symbol: "bookmark.fill",
                    title: bookmark.name,
                    row: .bookmark(index),
                    action: perform { handlers.openBookmark(bookmark) }
                )
            }
        }
    }

    // MARK: - Pinned footer

    /// Mirrors `MenuBuilder.buildPreferencesSection`: "What's new?" only appears
    /// while the running major version differs from the acknowledged one.
    private var showsWhatsNew: Bool {
        compareVersions(state.appMajorVersion, state.lastRevisedMajorVersion)
    }

    private var footerBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsWhatsNew {
                actionRow(
                    symbol: "sparkles",
                    title: "status_bar_whats_new".loco(),
                    row: .whatsNew,
                    action: perform(handlers.openChangelog)
                )
            }
            actionRow(
                symbol: "gearshape",
                title: "\("status_bar_preferences".loco())…",
                row: .preferences,
                action: perform(handlers.openPreferences)
            )
            actionRow(
                symbol: "power",
                title: "status_bar_quit".loco(),
                row: .quit,
                action: perform(handlers.quit)
            )
        }
    }

    // MARK: - Shared row chrome

    private func actionRow(
        symbol: String,
        title: String,
        row: DropdownPanelRow,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        PanelRow(isSelected: isSelected(row), action: action) { _ in
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
        .id(row)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: MenuStyleConstants.defaultFontSize - 2, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }

    /// Reuses an existing menu-header string as a control label by dropping its
    /// trailing colon ("Prep links:" → "Prep links"), so no new key is needed for
    /// the submenu/disclosure variants of the same wording.
    private func sectionLabel(_ key: String) -> String {
        var title = key.loco()
        while title.hasSuffix(":") { title.removeLast() }
        return title
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

    /// Closes the panel FIRST, then runs the action. Used for anything that opens
    /// a modal alert or another window (edit / delete / open in Reminders): the
    /// panel floats at the pop-up-menu level and would otherwise cover it.
    private func dismissThen(_ action: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        let dismiss = handlers.dismiss
        return {
            dismiss()
            action()
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
/// action, plain layout when it doesn't, plus the keyboard-selection highlight.
/// The hover state is handed to the content builder so a row can reveal a
/// trailing affordance — the whole point of the custom panel, since a plain
/// NSMenuItem can do neither.
private struct PanelRow<Content: View>: View {
    var isSelected = false
    let action: (@MainActor () -> Void)?
    @ViewBuilder let content: (Bool) -> Content

    @State private var isHovered = false

    var body: some View {
        content(isHovered)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(highlight)
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

    private var highlight: Color {
        if isSelected { return Color.accentColor.opacity(0.22) }
        if isHovered, action != nil { return Color.accentColor.opacity(0.18) }
        return .clear
    }
}

#Preview {
    DropdownPanelView(state: StatusBarMenuState(), handlers: DropdownPanelHandlers())
}
