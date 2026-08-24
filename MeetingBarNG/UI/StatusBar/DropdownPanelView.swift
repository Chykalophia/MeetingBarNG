//
//  DropdownPanelView.swift
//  MeetingBarNG
//
//  The SwiftUI dropdown panel — THE dropdown, and since `9c178efd` the only one.
//  A classic `NSMenu` built by `MenuBuilder` used to sit behind a preference as a
//  fallback; it was a second, feature-frozen renderer of this same content and
//  has been deleted.
//
//  Renders modules resolved by —
//  `DropdownCompositionPolicy.resolve(order:enabled:)` fed by the shared
//  `enabledRawValues(...)` helper — from a real `StatusBarMenuState` snapshot.
//  Reuses the existing `DaySummaryHeaderView`, `DayRelativeTimelineView` and
//  `MeetingSummaryView` for the top three modules.
//
//  NOTE ON THE MenuBuilder REFERENCES BELOW AND THROUGHOUT THIS FILE: they name a
//  DELETED type. They are kept as provenance — they record where a rule came from
//  and why it looks the way it does — and are NOT a live parity constraint. There
//  is nothing left to stay in sync with.
//
//  Phase B brought it to functional parity with the since-deleted menu, and past
//  it where SwiftUI can do things an NSMenuItem cannot:
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
//  Preferences UX overhaul Phase 1 made the shipping renderer honest. Five
//  preferences the NSMenu honoured were read by nothing here — the calendar-colour
//  dot was drawn unconditionally, no service icon was drawn at all, the time
//  column only ever showed the start, titles were never shortened and
//  `pastEventsAppereance = .hide` hid nothing. All five now run through the
//  shared code that outlived the menu (`StatusBarTitlePolicy.shortenTitle` and
//  the render/appearance rules extracted from it), and the five visual states the panel
//  silently dropped — declined dim/strikethrough, past dim, pending/tentative,
//  the [dismissed] marker and the running-meeting emphasis — are drawn here too.
//  Geometry comes from
//  the hostless `DropdownMetrics` / `AgendaRowLayout` instead of four unrelated
//  literal grids.
//
//  Presentation-only: every side effect (join, copy, edit, delete, quit, …) goes
//  out through an injected `DropdownPanelHandlers` closure, so the view has no
//  dependency on the status-bar controller.
//
//  Two consequences of this panel becoming the DEFAULT dropdown, fixed together:
//    • the NSMenu's "Quick Actions" subsection had no counterpart here, so five
//      actions (dismiss / remove all dismissals / open link from clipboard /
//      toggle the menu-bar meeting title / refresh sources) were reachable only
//      by keyboard shortcut. They are back — behind ONE "More actions" row in
//      the Join block, rather than five more top-level rows in a panel whose
//      whole point is that it is quiet. That row is a plain `PanelRow` that
//      flies out a native `NSMenu`, NOT a SwiftUI `Menu` — see the note on
//      `moreActionsRow` for why the SwiftUI control could not be made to sit on
//      the shared row grid. Camera check and World clock ride along from the
//      right-click quick-actions menu, since that is the only other place they
//      appear;
//    • `now` was a plain stored property, so while the panel was OPEN nothing
//      advanced: the countdown, the "in 25m" line, the timeline's now-marker and
//      the running/past row styling all froze at the instant it opened. `now` is
//      now the SEED for a live clock driven by the same `StatusBarTickPolicy`
//      that ticks the menu bar. Presentation only — it never refetches.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import AppKit
import Defaults
import KeyboardShortcuts
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
    /// Opens the in-app event editor. Distinct from `createMeeting`, which
    /// starts an online meeting on the configured service — one makes a calendar
    /// entry, the other makes a room to talk in.
    var newEvent: @MainActor () -> Void = {}
    /// Events in `[from, to)`, for the compact month grid's dots. The same shape
    /// as `CalendarWindowHandlers.fetchEvents` and wired to the same closure —
    /// the panel and the calendar window ask the repository one question, not two
    /// slightly different ones. Default returns nothing, so a caller that does
    /// not supply it simply gets no month dots.
    var fetchEvents: @MainActor (_ from: Date, _ to: Date) async throws -> [MBEvent] = { _, _ in [] }
    var refresh: @MainActor () -> Void = {}
    var openPreferences: @MainActor () -> Void = {}
    /// Wired for the Phase B quick-action rows (calendar window / command bar);
    /// the panel doesn't surface them yet.
    var openCalendar: @MainActor () -> Void = {}
    var openCommandBar: @MainActor () -> Void = {}
    var openChangelog: @MainActor () -> Void = {}
    var quit: @MainActor () -> Void = {}
    var dismiss: @MainActor () -> Void = {}

    // MARK: - Utility actions (the NSMenu's "Quick Actions" subsection)

    /// Detects a meeting link on the pasteboard and opens it — the NSMenu's
    /// "Open meeting from clipboard".
    var openLinkFromClipboard: @MainActor () -> Void = {}
    /// Flips `eventTitleFormat` between `.show` and `.generic`, i.e. hides or
    /// reveals the meeting title in the MENU BAR (not in this panel).
    var toggleMeetingTitleVisibility: @MainActor () -> Void = {}
    /// Opens the camera/mic pre-call preview with no event attached.
    var openCameraPreview: @MainActor () -> Void = {}
    var openWorldClock: @MainActor () -> Void = {}
    /// Dismisses the current/next meeting — the same action the NSMenu's
    /// quick-actions subsection offers, acting on the selected meeting.
    var dismissNextMeeting: @MainActor () -> Void = {}
    var undismissAllMeetings: @MainActor () -> Void = {}

    // MARK: - Per-event actions (NSMenu parity)

    var editEvent: @MainActor (MBEvent) -> Void = { _ in }
    /// Routes to the controller's destructive path: an NSAlert confirmation
    /// (including the recurring this-event / this-and-future choice) BEFORE the
    /// EventKit write.
    var deleteEvent: @MainActor (MBEvent) -> Void = { _ in }
    /// Click-to-copy for a detail string (location, organizer, attendee, notes).
    var copyText: @MainActor (String) -> Void = { _ in }
    var copyMeetingLink: @MainActor (MBEvent) -> Void = { _ in }
    var copyMeetingIdentifier: @MainActor (MBEvent) -> Void = { _ in }
    /// `nil` returns the event to the global reminder setting.
    var setReminderOverride: @MainActor (MBEvent, StartReminderOverride?) -> Void = { _, _ in }
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
    /// SEED for the panel's clock, injected so the first frame is drawn against
    /// the snapshot's moment (and so previews/tests are deterministic). Read
    /// `clock`, never this, for anything time-dependent — while the panel is open
    /// the clock advances and this does not.
    var now: Date = Date()
    /// When true, the panel expands to its full content height (no
    /// `maximumHeight` cap) and disables internal scrolling — used by the
    /// Display-tab preview so the outer ScrollView handles scrolling and
    /// nothing is clipped.
    var isPreview: Bool = false

    /// The stored module order. Read here (rather than passed in) so the panel
    /// resolves its layout through exactly the same policy the controller and the
    /// Display-tab preview use.
    @Default(.dropdownModuleOrder) private var dropdownModuleOrder

    /// Drives the whole layout grid — see `metrics` below. Stored as a raw string
    /// because the enum is hostless; an unrecognised value degrades to `.standard`
    /// rather than leaving the panel unrenderable.
    @Environment(\.colorScheme) private var colorScheme
    @Default(.dropdownDensity) private var dropdownDensityRaw
    @Default(.timelineStyle) private var timelineStyleRaw
    @Default(.timelineAppearance) private var timelineAppearanceRaw
    @Default(.meetingCardShowsProgress) private var showsMeetingCardProgress
    @Default(.dropdownHidesEmptyDays) private var hidesEmptyAgendaDays
    @Default(.dateMarkers) private var storedDateMarkers
    @Default(.dropdownCalendarWeekFold) private var calendarWeekFold
    @Default(.meetingCardShowsSectionLine) private var meetingCardShowsSectionLine
    @Default(.meetingCardShowsTimes) private var meetingCardShowsTimes
    @Default(.meetingCardShowsProvider) private var meetingCardShowsProvider
    @Default(.meetingCardShowsSource) private var meetingCardShowsSource
    @Default(.greetingShowsDate) private var greetingShowsDate

    private var dropdownDensity: DropdownDensity {
        DropdownDensity(rawValue: dropdownDensityRaw) ?? .standard
    }

    /// How close a meeting must be for its row action to look actionable.
    @Default(.eventActionHighlightMinutes) private var eventActionHighlightMinutes

    /// Rows one agenda section draws before the rest go behind "+N more".
    @Default(.dropdownMaxEventRows) private var dropdownMaxEventRows

    /// Months stepped away from today in the compact grid. Not persisted — the
    /// panel should always reopen on the current month.
    @State private var calendarMonthOffset = 0
    /// Dots for the visible month, filled by `loadMonthMarkers`.
    @State private var monthMarkers: [Date: [Color]] = [:]

    /// Sections the user has unfolded this time the panel is open. Not persisted:
    /// reopening should start compact again, or the cap stops doing its job.
    @State private var expandedAgendaDays: Set<AgendaDay> = []

    /// Index into `navigationRows` of the keyboard-selected row, or `nil` when
    /// nothing is selected yet (the state the panel opens in).
    @State private var selectionIndex: Int?
    /// Event ids whose inline detail disclosure is expanded.
    @State private var expandedEventIDs: Set<String> = []
    /// Drives the panel's key focus so Up/Down/Return reach `onMoveCommand` /
    /// `onKeyPress`. The window itself already becomes key on open.
    @FocusState private var isPanelFocused: Bool
    /// The advancing clock, published by `panelClock()`. `nil` until the first
    /// tick, which is what keeps the very first frame identical to `now`.
    @State private var tickedNow: Date?
    /// Holds the AppKit view the More-actions flyout anchors to. `@State` so the
    /// box survives the struct being rebuilt on every tick of the panel's clock.
    @State private var moreActionsAnchor = MenuAnchorBox()

    /// Pending spring-open from hovering the More-actions row, cancelled if the
    /// pointer leaves before the dwell elapses.
    @State private var moreActionsHoverTimer: DispatchWorkItem?

    /// Set once the flyout closes, so the pointer still resting on the row cannot
    /// immediately spring it open again. Cleared when the pointer actually leaves.
    @State private var moreActionsHoverDisarmed = false

    /// Nothing in the panel consulted this before Phase 1, despite five separate
    /// `easeOut(0.12)` animations.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The single layout grid (time column, marker slot, icon slot, paddings and
    /// gutter). Replaces four unrelated literal grids in one 330pt panel.
    /// The layout grid for the CURRENT density. Instance rather than static:
    /// density is a user preference, so the grid has to be read per render. Handed
    /// down through the environment so nested rows resolve the same one instead of
    /// each reaching for a global.
    private var metrics: DropdownMetrics { dropdownDensity.metrics }

    /// Dwell before hovering the More-actions row springs its flyout open. Long
    /// enough that sweeping the pointer down to Preferences or Quit passes over the
    /// row without firing, short enough to feel like a submenu rather than a wait.
    private static let moreActionsHoverDelay: TimeInterval = 0.25

    /// Same narrow width as the NSMenu dropdown's hosted rows, so the greeting,
    /// timeline and summary card keep their existing proportions.
    static var preferredWidth: CGFloat { MeetingSummaryView.preferredWidth }

    /// `nil` under Reduce Motion: the state change still happens, instantly.
    private var revealAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.12)
    }

    /// A long day scrolls inside the panel instead of growing past the screen.
    /// `DropdownPanelPlacement` trims this further when the display is short.
    static let maximumHeight: CGFloat = 760

    /// Shared with the window host so the AppKit corner mask matches the
    /// SwiftUI background exactly (no hairline at the corners).
    /// Read by the SwiftUI background AND by `WindowStylePolicy.applyRoundedCorners`,
    /// which masks the hosting window's layer. They must agree exactly: a mask
    /// tighter than the drawn shape clips it, looser and a hairline of window
    /// leaks past the corner.
    ///
    /// Liquid Glass carries a larger radius than flat material does — Apple's own
    /// glass surfaces are noticeably rounder — so the radius follows the surface
    /// rather than being one compromise value for both.
    static var cornerRadius: CGFloat {
        if #available(macOS 26.0, *) { 20 } else { 16 }
    }

    /// Fixed width of the trailing affordance slot on an event row. Reserved
    /// whether or not the row is hovered, so revealing the Join button never
    /// shifts the row's layout.

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(visibleModules.enumerated()), id: \.element) { pair in
                            if separatorIndices.contains(pair.offset) { separator }
                            moduleBlock(pair.element)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(width: Self.preferredWidth, alignment: .leading)
                }
                .scrollDisabled(isPreview)
                .onChange(of: selectionIndex) { _, _ in
                    guard let selectedRow else { return }
                    withAnimation(revealAnimation) {
                        proxy.scrollTo(selectedRow, anchor: .center)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            // A menu never shows a scrollbar. The panel scrolls only when a very
            // long day overflows `maximumHeight`, and even then the indicator stays
            // hidden so it reads as a menu rather than a scroll view.
            .scrollIndicators(.hidden)

            // OUTSIDE the scroll view, so Preferences and Quit are always on
            // screen. "Pinned" previously meant only that they could not be
            // hidden by the composer — they still scrolled away, and a dense day
            // (or the calendar module) pushed them past the fold, which reads as
            // the panel being broken rather than scrollable.
            separator
            footerBlock
                .padding(.bottom, 6)
                .frame(width: Self.preferredWidth, alignment: .leading)
        }
        .frame(width: Self.preferredWidth)
        .frame(maxHeight: isPreview ? .infinity : Self.maximumHeight)
        .background(panelSurface)
        .overlay(panelEdge)
        // Injected once, at the root, so every nested row renders against the
        // same grid rather than each resolving the density for itself.
        .environment(\.dropdownMetrics, metrics)
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
        .task { await panelClock() }
    }

    // MARK: - The panel's clock

    /// Advances `tickedNow` for as long as the panel is on screen.
    ///
    /// Structured concurrency rather than a `Timer`: `.task` cancels this the
    /// moment the view leaves the hierarchy, and the panel's window is BUILT PER
    /// OPEN and released after close (`WindowCoordinator.openDropdownPanel`), so
    /// closing the panel tears the view down and cancels the sleep. There is no
    /// timer object to retain, nothing to invalidate, and no wake-up while the
    /// panel is hidden — the previous panel is gone, not paused.
    ///
    /// The cadence is `StatusBarTickPolicy`, the same one the menu bar's clock
    /// uses, so the two can't drift into two different definitions of "a
    /// meaningful moment": every rendered row's start and end, each finished
    /// row's drop-out instant, and otherwise the next wall-clock minute.
    private func panelClock() async {
        // Distance between the injected seed and the real clock: ~0 in
        // production (the snapshot is built microseconds before the panel
        // opens), large in a preview or test that injects a fixed date — which
        // is what keeps such a panel advancing from ITS day instead of jumping
        // to today on the first tick.
        let seedOffset = now.timeIntervalSinceNow
        let transitions = tickTransitions

        while !Task.isCancelled {
            let current = clock
            let delay = StatusBarTickPolicy.delay(
                now: current,
                until: StatusBarTickPolicy.nextFireDate(now: current, transitions: transitions)
            )
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                // Cancelled: the panel closed. Nothing to clean up.
                return
            }
            withAnimation(revealAnimation) {
                tickedNow = Date().addingTimeInterval(seedOffset)
            }
        }
    }

    /// What this panel is rendering, described as instants: the boundaries of
    /// every event it can draw (today, tomorrow, and the meeting card's event,
    /// which the day lists need not contain).
    private var tickTransitions: [Date] {
        let events = state.todayEvents + state.tomorrowEvents + [state.nextEvent].compactMap { $0 }
        return StatusBarTickPolicy.transitionDates(
            boundaries: events.map {
                StatusBarTickPolicy.EventBoundary(start: $0.startDate, end: $0.endDate)
            },
            hideFinishedAfter: state.menu.hideFinishedEventsInMenu
                ? EventListWindow.endedGracePeriod
                : nil
        )
    }

    /// The instant everything time-dependent is drawn against: the injected seed
    /// until the first tick, the live clock afterwards.
    private var clock: Date { tickedNow ?? now }

    // MARK: - Composition

    /// The resolved, visible modules — the exact list the status-bar controller
    /// builds the real NSMenu from — minus the ones with nothing to render (so
    /// the panel never shows a stray separator).
    private var visibleModules: [DropdownModule] {
        DropdownCompositionPolicy.resolve(
            order: dropdownModuleOrder,
            enabled: DropdownCompositionPolicy.enabledRawValues(
                greeting: state.showGreetingHeader,
                // The style picker is the timeline's on/off now — see
                // `TimelineSpan`.
                timeline: timelineStyle.isVisible,
                meeting: state.menu.showMeetingControlInMenu,
                agenda: state.menu.showAgendaInMenu,
                join: state.menu.showJoinSectionInMenu,
                bookmarks: state.menu.showBookmarksInMenu,
                calendar: state.menu.showCalendarInMenu
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
        case .calendar: state.hasSelectedCalendars
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
        case .calendar: calendarBlock
        }
    }

    /// Which module indices get a rule above them. One rule above the run of
    /// action lists — see `DropdownSeparatorPolicy`.
    private var separatorIndices: Set<Int> {
        DropdownSeparatorPolicy.separatorIndices(for: visibleModules)
    }

    /// Inset to the row grid, not full-bleed. A rule that runs into the panel's
    /// corners fights the rounded surface and makes the panel read as a stack of
    /// strips rather than one sheet.
    private var separator: some View {
        Divider()
            .padding(.horizontal, metrics.rowOuterPadding)
            .padding(.vertical, 5)
    }

    // MARK: - Keyboard navigation

    /// What the panel is rendering, described hostlessly so the row order — and
    /// therefore the keyboard behavior — is unit-tested in
    /// `DropdownPanelNavigationTests` rather than only in the UI.
    private var navigationContent: DropdownPanelContent {
        // Capped, not raw: arrow keys must never land on a row that was withheld.
        let today = capped(todayRenderedEvents, day: .today)
        let tomorrow = capped(tomorrowRenderedEvents, day: .tomorrow)
        return DropdownPanelContent(
            modules: visibleModules,
            meetingEventID: state.nextEvent?.id,
            todayEventIDs: today.shown.map(\.id),
            reminderIDs: state.todayReminders.map(\.id),
            tomorrowEventIDs: tomorrow.shown.map(\.id),
            todayHasHiddenEvents: today.hidden > 0,
            tomorrowHasHiddenEvents: tomorrow.hidden > 0,
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
        case .showMoreEvents(let day):
            // Unlike every other row this one does NOT dismiss the panel — the
            // point is to keep reading the list that just grew.
            expandAgendaDay(day)
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
                symbolName: greetingSymbolName(summary.timeOfDay),
                actions: headerActions
            )
        }
    }

    /// The header's trailing quick actions.
    ///
    /// These are shortcuts to things already reachable further down the panel, put
    /// where the eye lands first. Deliberately three: the header is a summary, and
    /// a fourth icon starts competing with the text it is meant to support.
    private var headerActions: [DaySummaryHeaderAction] {
        [
            DaySummaryHeaderAction(
                id: "create",
                symbol: "plus",
                help: "status_bar_section_join_create_meeting".loco(),
                run: perform(handlers.createMeeting)
            ),
            DaySummaryHeaderAction(
                id: "search",
                symbol: "magnifyingglass",
                help: "command_bar_open".loco(),
                run: dismissThen(handlers.openCommandBar)
            ),
            DaySummaryHeaderAction(
                id: "preferences",
                symbol: "gearshape",
                help: "status_bar_preferences".loco(),
                run: perform(handlers.openPreferences)
            )
        ]
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
        // "today" is dropped once the date is named: three segments plus a
        // redundant word wrapped this line onto a second row and grew the header.
        let dated = greetingShowsDate
        let countText: String
        switch summary.eventCount {
        case 0:
            countText = (dated ? "menu_day_summary_no_events_dated" : "menu_day_summary_no_events")
                .loco()
        case 1:
            countText = (dated
                ? "menu_day_summary_event_count_one_dated"
                : "menu_day_summary_event_count_one").loco(summary.eventCount)
        default:
            countText = (dated
                ? "menu_day_summary_event_count_other_dated"
                : "menu_day_summary_event_count_other").loco(summary.eventCount)
        }
        let freeText = "menu_day_summary_focus_time".loco(formattedFreeTime(summary.freeMinutes))
        // The date leads: it answers "which day am I looking at" before the
        // counts describe it, and it frees the agenda's head to be a plain label.
        guard dated else { return "\(countText) · \(freeText)" }
        return "\(greetingDateText(clock)) · \(countText) · \(freeText)"
    }

    /// "Tue 28" — deliberately shorter than the agenda's "Tue, 28 Jul".
    ///
    /// Three segments plus a month name overran the header's ~197pt of text
    /// width and truncated mid-word ("6h 31m f…"). The month is the least
    /// informative part when the line is describing TODAY, so it goes first.
    private func greetingDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = I18N.instance.locale
        formatter.setLocalizedDateFormatFromTemplate("Ed")
        return formatter.string(from: date)
    }

    private func formattedFreeTime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0, mins > 0 { return "\(hours)h \(mins)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(mins)m"
    }

    // MARK: - Timeline

    // MARK: - Up next

    /// The "Next · <title> — in 24m" card with a bar filling toward the start.
    ///
    /// Deliberately meeting-relative rather than the reference's year/day
    /// progress: "1.2% of today" is trivia, this is actionable. The bar reaches
    /// full at exactly the moment `eventActionHighlightMinutes` un-mutes the Join
    /// button and boldens the menu bar — one threshold made visible in a third
    /// place, rather than a fourth unrelated setting.
    /// The countdown bar under the meeting card.
    ///
    /// This used to be its own `upNext` MODULE, which meant the panel could show
    /// the same meeting twice — a card naming it and a bar counting down to it,
    /// each with its own toggle and its own place in the order. They were one
    /// idea wearing two hats, so the bar is now a display option ON the card.
    @ViewBuilder
    private func meetingProgressBar(_ event: MBEvent) -> some View {
        // Nothing to draw until the meeting is inside the fill window. An empty
        // track for a meeting three hours out is honest and nearly invisible, and
        // it leaves the countdown floating under a bar that never moves.
        //
        // Shares `MeetingProgressPolicy` with the menu-bar indicator, so the two
        // fill on the same schedule and change colour at the same instant rather
        // than each carrying their own copy of "an hour out".
        if showsMeetingCardProgress,
           let progress = MeetingProgressPolicy.presentation(
               start: event.startDate,
               end: event.endDate,
               now: clock,
               leadMinutes: eventActionHighlightMinutes
           ) {
            VStack(alignment: .leading, spacing: 5) {
                upNextBar(progress)
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Text(upNextCountdown(event))
                        .font(.system(size: metrics.secondaryFontSize - 1))
                        .foregroundStyle(progress.phase == .upcoming ? .secondary : Color.accentColor)
                        .monospacedDigit()
                }
            }
            .padding(.top, 2)
        }
    }

    private func upNextBar(_ progress: MeetingProgressPresentation) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(
                        progress.phase == .upcoming
                            ? Color.accentColor.opacity(0.55)
                            : Color.accentColor
                    )
                    .frame(width: progress.fraction * proxy.size.width)
            }
        }
        .frame(height: 4)
    }

    private func upNextCountdown(_ event: MBEvent) -> String {
        if event.startDate <= clock {
            return "dropdown_panel_up_next_now".loco()
        }
        let minutes = Int((event.startDate.timeIntervalSince(clock) / 60).rounded())
        if minutes >= 60 {
            return "dropdown_panel_up_next_in_hm".loco(minutes / 60, minutes % 60)
        }
        return "dropdown_panel_up_next_in_m".loco(max(minutes, 0))
    }

    // MARK: - Calendar

    /// A compact month grid, carded.
    ///
    /// Uses `CompactMonthGridView` rather than the window's `CalendarGridView`,
    /// which is floored at 460pt against this panel's 330. The two share
    /// `MonthGridLayout` — the hostless week/today computation — and disagree only
    /// about chrome, which is the correct seam: dates are policy, layout is not.
    private var calendarBlock: some View {
        PanelCard {
            CompactMonthGridView(
                month: visibleCalendarMonth,
                now: clock,
                calendar: panelCalendar,
                markers: calendarMarkers,
                dateMarkers: DateMarkerCodec.decodeAll(storedDateMarkers),
                isWeekFold: calendarWeekFold,
                onStep: { step in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                        calendarMonthOffset += step
                    }
                },
                onSelect: { _ in handlers.openCalendar() },
                onToggleFold: {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                        calendarWeekFold.toggle()
                        // The offset counted months; after the fold it counts
                        // weeks. Carrying it over would jump the grid somewhere
                        // arbitrary, so folding always lands on the current
                        // period — which is what someone folding to "this week"
                        // means anyway.
                        calendarMonthOffset = 0
                    }
                },
                onReturnToToday: {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                        calendarMonthOffset = 0
                    }
                },
                isSteppedAway: calendarMonthOffset != 0
            )
            // Keyed on the anchor, so stepping cancels the previous request
            // rather than racing it — two months in flight could otherwise land
            // out of order and leave the wrong dots on screen. The fold is part
            // of the key because it changes what the offset means.
            .task(id: "\(calendarWeekFold)-\(calendarMonthOffset)") { await loadMonthMarkers() }
        }
    }

    private var panelCalendar: Calendar {
        CalendarGridViewModel.defaultCalendar()
    }

    /// The date the grid is anchored on. The step UNIT follows the fold, so a
    /// folded week pages by weeks — see `MonthGridLayout.anchor`.
    private var visibleCalendarMonth: Date {
        MonthGridLayout.anchor(
            from: clock,
            offset: calendarMonthOffset,
            isWeekFold: calendarWeekFold,
            calendar: panelCalendar
        )
    }

    /// Event dots for the visible month.
    ///
    /// The panel's own state carries today and tomorrow only, so those two days
    /// are drawn immediately from what is already in hand and the rest of the
    /// month arrives from `loadMonthMarkers`. Merging rather than replacing is
    /// what stops the grid flickering empty on every month change: the days the
    /// panel already knows about never lose their dots while the fetch runs.
    private var calendarMarkers: [Date: [Color]] {
        var byDay = monthMarkers
        for event in visibleEvents(state.todayEvents) + visibleEvents(state.tomorrowEvents) {
            let day = panelCalendar.startOfDay(for: event.startDate)
            guard byDay[day] == nil else { continue }
            byDay[day] = [calendarColor(for: event)]
        }
        return byDay
    }

    /// Fetches the visible month's events and reduces them to one dot list per
    /// day.
    ///
    /// Driven by `.task(id:)` on the grid, so switching months cancels the
    /// in-flight request and a closing panel cancels it too — the async lifecycle
    /// that made this "real work" is handled by the view's own identity rather
    /// than by hand.
    ///
    /// A failure leaves the previous dots alone. The grid's job here is
    /// orientation, and silently keeping slightly stale dots is better than
    /// blanking the month because one fetch lost a race with a calendar resync.
    private func loadMonthMarkers() async {
        let calendar = panelCalendar
        guard let interval = calendar.dateInterval(of: .month, for: visibleCalendarMonth) else {
            return
        }
        // A month grid shows leading and trailing days from its neighbours, so
        // fetch a week either side or those cells are always empty.
        let from = calendar.date(byAdding: .day, value: -7, to: interval.start) ?? interval.start
        let to = calendar.date(byAdding: .day, value: 7, to: interval.end) ?? interval.end

        guard let events = try? await handlers.fetchEvents(from, to) else { return }
        guard !Task.isCancelled else { return }

        var byDay: [Date: [Color]] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.startDate)
            byDay[day, default: []].append(calendarColor(for: event))
        }
        monthMarkers = byDay
    }

    private func calendarColor(for event: MBEvent) -> Color {
        Color(nsColor: event.calendar.color)
    }

    /// Carded: the timeline is a widget with its own horizontal coordinate system
    /// (a whole day mapped to the panel's width), so a frame helps the eye read it
    /// as one object rather than as another row.
    /// An unrecognised stored value reads back as `.relative` — the shipping
    /// look — rather than leaving the bar unable to frame itself.
    private var timelineStyle: TimelineSpan {
        TimelineSpan(rawValue: timelineStyleRaw) ?? .relative
    }

    private var timelineAppearance: TimelineAppearance {
        TimelineAppearance(rawValue: timelineAppearanceRaw) ?? .track
    }

    private var timelineBlock: some View {
        let timeline = DayRelativeTimelineView(
            segments: timelineSegments,
            currentDate: clock,
            timeFormat: state.timeFormat,
            style: timelineStyle,
            appearance: timelineAppearance
        )
        return PanelCard {
            timeline
                .frame(
                    // Derived from the card's own inset rather than a literal, so
                    // the bar keeps clear of the border at every density.
                    width: Self.preferredWidth
                        - 2 * (metrics.rowOuterPadding + metrics.cardHorizontalPadding),
                    height: timeline.preferredHeight
                )
        }
    }

    private var timelineSegments: [DaySegment] {
        let startOfDay = Calendar.current.startOfDay(for: clock)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? clock
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
            // Carded like the timeline and the up-next bar. It used to be the one
            // module that floated on the panel background, which made the panel's
            // most important element read as the least deliberate.
            PanelCard {
                VStack(alignment: .leading, spacing: 0) {
                    MeetingSummaryView(
                        presentation: presentation,
                        onJoin: event.meetingLink == nil
                            ? nil
                            : { handlers.joinEvent(event); handlers.dismiss() },
                        isActionImminent: isActionImminent(event),
                        horizontalPadding: 0
                    )
                    meetingProgressBar(event)
                }
                // Same surface as every other selectable row — see `PanelHighlight`.
                .background(
                    PanelHighlight(
                        isSelected: isSelected(.meetingSummary(event.id)),
                        isHovered: false
                    )
                )
            }
            // Right-click parity: the whole per-event action set the NSMenu puts
            // behind the card's "Actions" submenu.
            .contextMenu { eventContextMenu(event) }
            .id(DropdownPanelRow.meetingSummary(event.id))
        } else {
            emptyStateBlock
        }
    }

    /// The meeting card's copy, from the shared `MeetingSummaryPresenter`.
    ///
    /// `clock`, not `Date()`, so the countdown re-reads as the panel ticks.
    private func meetingSummaryPresentation(for event: MBEvent) -> MeetingSummaryPresentation {
        var presentation = MeetingSummaryPresenter.presentation(
            for: event,
            timeFormat: state.timeFormat,
            now: clock,
            fields: meetingCardFields
        )
        // `showMeetingServiceIcon` governs the meeting card too. Applied here
        // rather than inside the presenter because it is a PANEL display
        // setting, not part of what the copy says.
        if !state.menu.showMeetingServiceIcon {
            presentation.meetingService = nil
        }
        return presentation
    }

    private var meetingCardFields: MeetingCardFields {
        MeetingCardFields(
            showsSectionLine: meetingCardShowsSectionLine,
            showsTimes: meetingCardShowsTimes,
            showsProvider: meetingCardShowsProvider,
            showsSource: meetingCardShowsSource
        )
    }

    /// The honest reason there is no meeting to show, plus the one action that
    /// can fix it — the same mapping `MenuBuilder.buildEmptyMeetingControlSection`
    /// uses, with the auth/permission repairs routed to Preferences.
    @ViewBuilder
    private var emptyStateBlock: some View {
        let reason = state.emptyStateReason ?? .noUpcomingMeetings
        VStack(alignment: .leading, spacing: 2) {
            Text(emptyStateTitle(reason))
                .font(.system(size: metrics.rowFontSize, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, metrics.sectionHeaderInset)
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
        // Counts the events that would actually be DRAWN, not the raw ones: a day
        // whose every meeting was filtered out as declined is empty as far as the
        // reader is concerned, and should hide on the same terms.
        //
        // Summary mode renders no event rows, so `tomorrowRenderedEvents` is empty
        // by design there — it reads the visible list directly instead.
        let renderedCount = tomorrowDisplayMode == .today_n_tomorrow_summary
            ? visibleEvents(state.tomorrowEvents).count
            : tomorrowRenderedEvents.count
        return AgendaSectionVisibilityPolicy.showsSection(
            eventCount: renderedCount,
            isIncludedByPeriod: state.events.showEventsForPeriod.includesTomorrow,
            hidesEmptyDays: hidesEmptyAgendaDays,
            isAnchorDay: false
        )
    }

    private var tomorrowDisplayMode: ShowEventsForPeriod {
        state.events.showEventsForPeriod
    }

    /// The tomorrow events the section would render before the row cap applies —
    /// the single source both `agendaBlock` and `navigationContent` read, so the
    /// rows drawn and the rows the keyboard walks cannot drift apart. Summary mode
    /// renders no event rows at all, hence empty.
    private var tomorrowRenderedEvents: [MBEvent] {
        DropdownEventVisibility.tomorrowRendered(
            state.tomorrowEvents,
            menu: state.menu,
            display: state.events,
            isDeclined: isDeclined,
            now: clock
        )
    }

    private var todayRenderedEvents: [MBEvent] {
        visibleEvents(state.todayEvents)
    }

    /// Splits a section's events into the ones it draws and the number it holds
    /// back. A section the user has expanded, or a cap of `0`, withholds nothing.
    private func capped(_ events: [MBEvent], day: AgendaDay) -> (shown: [MBEvent], hidden: Int) {
        let limit = dropdownMaxEventRows
        guard limit > 0, !expandedAgendaDays.contains(day), events.count > limit else {
            return (events, 0)
        }
        return (Array(events.prefix(limit)), events.count - limit)
    }

    private var agendaBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            dateSection(
                title: "status_bar_section_today".loco(),
                date: clock,
                events: todayRenderedEvents,
                day: .today
            )
            remindersRows
            if showsTomorrowSection {
                separator
                let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: clock) ?? clock
                switch tomorrowDisplayMode {
                case .today_n_tomorrow, .today_n_tomorrow_next:
                    dateSection(
                        title: "status_bar_section_tomorrow".loco(),
                        date: tomorrowDate,
                        events: tomorrowRenderedEvents,
                        day: .tomorrow
                    )
                case .today_n_tomorrow_summary:
                    tomorrowSummarySection(
                        date: tomorrowDate,
                        events: visibleEvents(state.tomorrowEvents)
                    )
                default:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder
    private func tomorrowSummarySection(date: Date, events: [MBEvent]) -> some View {
        let title = "status_bar_section_tomorrow".loco()
        sectionHeader(title, date: date)
        Text(DropdownEventVisibility.tomorrowSummaryText(visibleTomorrowEvents: events))
            .font(.system(size: metrics.rowFontSize))
            .foregroundStyle(.secondary)
            .padding(.horizontal, metrics.sectionHeaderInset)
            .padding(.vertical, 4)
    }

    @ViewBuilder
    private func dateSection(
        title: String,
        date: Date,
        events: [MBEvent],
        day: AgendaDay
    ) -> some View {
        // Only today's heading carries the create chip: "new meeting" means one
        // starting now-ish, and offering it above tomorrow would imply it lands
        // there.
        sectionHeader(title, date: date, showsCreateAction: showsAgendaCreateAction(day))
        if events.isEmpty {
            Text("status_bar_section_date_nothing".loco(title.lowercased()))
                .font(.system(size: metrics.rowFontSize))
                .foregroundStyle(.secondary)
                .padding(.horizontal, metrics.sectionHeaderInset)
                .padding(.vertical, 4)
        }
        let section = capped(events, day: day)
        ForEach(section.shown, id: \.id) { event in
            eventRow(event)
        }
        if section.hidden > 0 {
            showMoreRow(day: day, hidden: section.hidden)
        }
    }

    /// Reveals the events the cap withheld, in place.
    ///
    /// In place rather than opening the calendar window: the panel already
    /// scrolls, so the events appear where the user is already looking instead of
    /// in a second surface they then have to dismiss. Deliberately one-way — there
    /// is no re-collapse, because the panel closes on its own and reopens capped,
    /// which makes a collapse control a row that earns its space roughly never.
    private func showMoreRow(day: AgendaDay, hidden: Int) -> some View {
        actionRow(
            symbol: "chevron.down",
            title: hidden == 1
                ? "status_bar_section_show_more_events_one".loco(hidden)
                : "status_bar_section_show_more_events_other".loco(hidden),
            row: .showMoreEvents(day),
            action: { expandAgendaDay(day) }
        )
    }

    private func expandAgendaDay(_ day: AgendaDay) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
            _ = expandedAgendaDays.insert(day)
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
        let layout = agendaRowLayout
        let appearance = rowAppearance(for: event)
        return HStack(spacing: metrics.columnSpacing) {
            if layout.timeColumnWidth > 0 {
                eventTimeColumn(event, width: layout.timeColumnWidth)
            }
            // Only the in-row position is DRAWN here. `AgendaRowLayout` already
            // solves the far-left placement (a negative inset that escapes
            // PanelRow's padding), but nothing sets that position until the
            // Agenda gear ships, so there is no view code for it yet.
            if layout.resolvedPosition == .betweenTimeAndTitle,
                let markerFrame = layout.markerFrame {
                calendarMarker(
                    event,
                    marker: layout.marker,
                    frame: markerFrame,
                    isHollow: appearance.markerIsHollow
                )
            }
            if layout.serviceIconOrigin != nil {
                serviceIcon(event)
            }
            // Title and badge share the row's flexible space, and the fade is
            // applied to THAT box rather than to the text: a mask on the text
            // alone would fade the tail of every short title, because a Text is
            // only as wide as its content. Filling the space first means the
            // fade zone sits in empty air until a title is actually long enough
            // to reach it.
            HStack(spacing: 6) {
                // Priority so the title wins the space outright. Without it the
                // Spacer is an equally flexible sibling and takes roughly half,
                // truncating titles that would otherwise have fit.
                eventTitle(event, appearance: appearance)
                    .layoutPriority(1)
                if appearance.isRunning, appearance.showsActiveEmphasis {
                    runningBadge
                }
                Spacer(minLength: 0)
            }
            .mask(titleFadeMask)
            trailingAffordance(event, isHovered: isHovered)
            disclosureChevron(event, isHovered: isHovered)
        }
    }

    /// Softens where a long title meets the row's trailing controls.
    ///
    /// A hard `…` butted against the Join button reads as the text hitting a
    /// wall. Fading it instead lets the title run out UNDER the control, which is
    /// what the mockup does. Truncation stays on underneath as the fallback: a
    /// title long enough to need it still gets its ellipsis, now inside the
    /// faded stretch rather than against a hard edge.
    private var titleFadeMask: some View {
        HStack(spacing: 0) {
            Rectangle()
            LinearGradient(
                colors: [.black, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 20)
        }
    }

    /// The row grid for the current preferences. Marker SHAPE and POSITION are
    /// not user-settable yet (Phase 6); `showEventCalendarColor` selects between
    /// a dot and nothing, which is what that switch always claimed to do.
    private var agendaRowLayout: AgendaRowLayout {
        AgendaRowLayout.resolve(
            metrics: metrics,
            marker: state.menu.showEventCalendarColor ? .dot : .none,
            position: .betweenTimeAndTitle,
            timeColumn: agendaTimeColumn,
            showsServiceIcon: state.menu.showMeetingServiceIcon
        )
    }

    private var agendaTimeColumn: AgendaTimeColumn {
        state.statusBar.showEventEndTime ? .startAndEnd : .startOnly
    }

    /// Start time, with the end time stacked underneath when the user asked for
    /// it. Stacked rather than "10:00 – 10:30" on one line: in 12-hour format
    /// that single line costs ~125pt of a 298pt content box and the title becomes
    /// unreadable. See `DropdownMetrics.timeColumnWidth(for:)`.
    private func eventTimeColumn(_ event: MBEvent, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eventStartText(event))
            if let endText = eventEndText(event) {
                Text(endText)
                    .foregroundStyle(.tertiary)
            }
        }
        // `metrics.secondaryFontSize`, not a hardcoded 12: the time column was
        // the one part of a row that density never reached, so Small and Large
        // moved the title and left the time behind.
        .font(.system(size: metrics.secondaryFontSize).monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func calendarMarker(
        _ event: MBEvent,
        marker: AgendaMarker,
        frame: AgendaRowLayout.MarkerFrame,
        isHollow: Bool
    ) -> some View {
        let color = Color(nsColor: event.calendar.color)
        Group {
            switch marker {
            case .none:
                EmptyView()
            case .dot:
                if isHollow {
                    Circle().strokeBorder(color, lineWidth: 1.5)
                } else {
                    Circle().fill(color)
                }
            case .leftBorderBar:
                Capsule().fill(color)
            }
        }
        .frame(width: frame.width, height: frame.height)
    }

    /// The meeting service's logo. The slot is reserved for every row (the frame
    /// is applied unconditionally) so titles stay on one grid whether or not a
    /// given meeting has a link — but no "no online session" placeholder is
    /// drawn, which is the one thing the NSMenu could not avoid.
    private func serviceIcon(_ event: MBEvent) -> some View {
        Group {
            if let link = event.meetingLink {
                Image(nsImage: getIconForMeetingService(link.service))
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: metrics.serviceIconWidth, height: metrics.serviceIconWidth)
    }

    private func eventTitle(_ event: MBEvent, appearance: EventRowAppearance) -> some View {
        Text(eventTitleText(event))
            .font(.system(
                size: metrics.rowFontSize,
                weight: appearance.isRunning && appearance.showsActiveEmphasis
                    ? .semibold
                    : .regular
            ))
            .foregroundStyle(appearance.isDimmed ? Color.secondary : Color.primary)
            .strikethrough(appearance.isStruckThrough)
            .lineLimit(1)
    }

    /// The running-meeting glyph the NSMenu appends to the title as a text
    /// attachment (`MenuBuilder.applyRunningEventAppearance`). Weight alone is a
    /// weak signal, and it is invisible next to an already-bold row.
    private var runningBadge: some View {
        Image(nsImage: MenuStyleConstants.iconNamed(MenuStyleConstants.runningIconName))
            .resizable()
            .scaledToFit()
            .frame(width: 11, height: 11)
            .accessibilityLabel("status_bar_control_current_meeting".loco())
    }

    /// Shortening runs through `StatusBarTitlePolicy.shortenTitle`, the same helper
    /// the deleted NSMenu used, so the menu-bar title and this panel agree about
    /// what a shortened title looks like.
    ///
    /// The menu's extra "uncapped" fallback cap was deliberately NOT copied: it
    /// existed only because an NSMenu sizes itself to its widest item. This panel
    /// is a fixed 330pt and truncates visually, so "don't shorten" can mean it.
    private func eventTitleText(_ event: MBEvent) -> String {
        let rawTitle: String? = event.title.isEmpty ? nil : event.title
        var title = state.menu.shortenEventTitle
            ? StatusBarTitlePolicy.shortenTitle(
                rawTitle,
                limit: state.menu.menuEventTitleLength,
                noTitle: "status_bar_no_title".loco()
            )
            : rawTitle ?? "status_bar_no_title".loco()
        if isDismissed(event) {
            title = "[\("status_bar_event_dismissed_mark".loco())] \(title)"
        }
        return title
    }

    // MARK: - Event row appearance (the five states the panel used to drop)

    /// Mirrors `MenuBuilder.baseEventItemStyle` / `applyPastEventAppearance` /
    /// `applyRunningEventAppearance`, translated from NSAttributedString
    /// attributes into things SwiftUI can draw.
    private struct EventRowAppearance {
        var isDimmed = false
        var isStruckThrough = false
        var isRunning = false
        /// False for declined and self-booked-inactive rows: the menu suppresses
        /// the running badge and the bold weight for those.
        var showsActiveEmphasis = true
        /// Stands in for AppKit's dotted, by-word underline, which SwiftUI cannot
        /// draw. A hollow marker is a SHAPE difference, so it also survives
        /// greyscale and colour-vision deficiency — which the underline did not.
        var markerIsHollow = false
    }

    private func rowAppearance(for event: MBEvent) -> EventRowAppearance {
        var appearance = EventRowAppearance()
        appearance.isRunning = event.startDate <= clock && event.endDate > clock

        if isDeclined(event) {
            if state.events.declinedEventsAppearance == .show_inactive {
                appearance.isDimmed = true
            } else {
                appearance.isStruckThrough = true
            }
            appearance.showsActiveEmphasis = false
        }

        if !event.isAllDay,
            state.events.nonAllDayEvents == .show_inactive_without_meeting_link,
            event.meetingLink == nil {
            appearance.isDimmed = true
        }

        applyParticipationStyle(
            statusMatches: event.participationStatus == .pending,
            showInactive: state.events.showPendingEvents == .show_inactive,
            showUnderlined: state.events.showPendingEvents == .show_underlined,
            to: &appearance
        )
        applyParticipationStyle(
            statusMatches: event.participationStatus == .tentative,
            showInactive: state.events.showTentativeEvents == .show_inactive,
            showUnderlined: state.events.showTentativeEvents == .show_underlined,
            to: &appearance
        )

        if event.attendees.isEmpty, state.events.personalEventsAppearance == .show_inactive {
            appearance.isDimmed = true
            appearance.showsActiveEmphasis = false
        }

        // Past events dim only when asked to. The panel used to dim every
        // finished row unconditionally, so `.show_active` did nothing.
        if event.endDate < clock, state.events.pastEventsAppearance == .show_inactive {
            appearance.isDimmed = true
        }

        return appearance
    }

    private func applyParticipationStyle(
        statusMatches: Bool,
        showInactive: Bool,
        showUnderlined: Bool,
        to appearance: inout EventRowAppearance
    ) {
        guard statusMatches else { return }
        if showInactive {
            appearance.isDimmed = true
        } else if showUnderlined {
            appearance.markerIsHollow = true
        }
    }

    private func isDeclined(_ event: MBEvent) -> Bool {
        event.participationStatus == .declined || event.status == .canceled
    }

    /// The hover-revealed Join button. The slot is a fixed width and the two
    /// states are stacked, so revealing the button on hover never re-lays-out the
    /// row — the thing a plain NSMenuItem could never do.
    @ViewBuilder
    private func trailingAffordance(_ event: MBEvent, isHovered: Bool) -> some View {
        if event.meetingLink != nil {
            let revealed = isHovered || isSelected(.event(event.id))
            let actionable = isActionImminent(event)
            Image(systemName: "video.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .opacity(revealed ? 0 : 1)
                // Only the resting glyph occupies layout. The pill is an OVERLAY,
                // so revealing it neither reflows the row nor makes every linked
                // event surrender pill-width of title while hidden.
                .frame(width: metrics.trailingGlyphWidth, alignment: .trailing)
                .overlay(alignment: .trailing) {
                    Text("notifications_meetingbar_join_event_action".loco())
                        .font(.system(size: 10, weight: actionable ? .semibold : .regular))
                        .foregroundStyle(
                            actionable ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary)
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        // Same surface as the meeting card's Join button — one
                        // affordance at two sizes.
                        .joinControlSurface(isActionImminent: actionable)
                        .fixedSize()
                        .opacity(revealed ? 1 : 0)
                        .contentShape(Capsule())
                        .onTapGesture(perform: perform { handlers.joinEvent(event) })
                        // Hidden from the pointer while hidden from the eye, or an
                        // invisible pill would eat clicks aimed at the title.
                        .allowsHitTesting(revealed)
                }
                .animation(revealAnimation, value: revealed)
                .animation(revealAnimation, value: actionable)
        }
    }

    /// Whether this event's action is worth acting on RIGHT NOW. `clock`, not
    /// `now`, so a control un-mutes on its own as its meeting approaches while the
    /// panel sits open. The rule itself lives in `EventActionProminence` because
    /// the meeting card and the classic NSMenu apply the same one.
    private func isActionImminent(_ event: MBEvent) -> Bool {
        EventActionProminence.isImminent(
            start: event.startDate,
            end: event.endDate,
            now: clock,
            leadMinutes: eventActionHighlightMinutes
        )
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
            .animation(revealAnimation, value: revealed)
    }

    private func isExpanded(_ event: MBEvent) -> Bool {
        expandedEventIDs.contains(event.id)
    }

    private func toggleExpansion(_ event: MBEvent) {
        withAnimation(revealAnimation) {
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
            prepLinkDetails(event)
        }
        .padding(.leading, metrics.detailIndent)
        .padding(.trailing, metrics.sectionHeaderInset)
        .padding(.bottom, 4)
    }

    /// Meeting-prep links, inline. They were reachable only from the right-click
    /// submenu — i.e. only if you already knew they existed. The context-menu
    /// entry stays; this is an addition, not a move.
    @ViewBuilder
    private func prepLinkDetails(_ event: MBEvent) -> some View {
        let links = prepLinks(for: event)
        if !links.isEmpty {
            detailLabel(sectionLabel("status_bar_submenu_prep_links_title"))
            ForEach(links, id: \.url) { link in
                if let url = URL(string: link.url) {
                    prepLinkRow(title: link.displayTitle, url: url)
                }
            }
        }
    }

    private func prepLinkRow(title: String, url: URL) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            Text(title)
                .font(.system(size: metrics.rowFontSize - 1))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .pointerStyle(.link)
        .onTapGesture(perform: perform { handlers.openURL(url) })
        .help(url.absoluteString)
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
            .font(.system(size: metrics.rowFontSize - 2, weight: .semibold))
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
                .font(.system(size: metrics.rowFontSize - 1))
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

    /// Per-event reminder time.
    ///
    /// Presets only, no custom picker: a submenu is a place for a decision, not
    /// a form, and the useful answers here are coarse. "Use the default" is
    /// listed rather than implied so returning to it is one click, not a guess
    /// about which preset happens to match the global setting.
    @ViewBuilder
    private func reminderMenu(_ event: MBEvent) -> some View {
        Menu("status_bar_submenu_remind_me".loco()) {
            Button("status_bar_submenu_remind_default".loco()) {
                perform { handlers.setReminderOverride(event, nil) }()
            }
            Button("status_bar_submenu_remind_never".loco()) {
                perform { handlers.setReminderOverride(event, .suppressed) }()
            }
            Divider()
            Button("status_bar_submenu_remind_at_start".loco()) {
                perform { handlers.setReminderOverride(event, .offset(0)) }()
            }
            ForEach([1, 5, 10, 15, 30, 60], id: \.self) { minutes in
                Button("status_bar_submenu_remind_minutes".loco(minutes)) {
                    perform {
                        handlers.setReminderOverride(event, .offset(TimeInterval(minutes * 60)))
                    }()
                }
            }
        }
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
            // Only when the URL actually carries one. Most services have no
            // usable id, and a disabled row in a menu this long is noise —
            // same reasoning as the Join row, which hides rather than greys.
            if let identifier = event.meetingIdentifier {
                Button(identifier.kind == .room
                    ? "status_bar_submenu_copy_meeting_room".loco()
                    : "status_bar_submenu_copy_meeting_id".loco()) {
                    perform { handlers.copyMeetingIdentifier(event) }()
                }
            }
        }
        alternateLinksMenu(event)
        prepLinksMenu(event)
        reminderMenu(event)
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
            HStack(spacing: metrics.columnSpacing) {
                Text(reminderTimeText(reminder))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: metrics.timeColumnWidth, alignment: .leading)
                Image(systemName: reminder.isCompleted ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: perform { handlers.completeReminder(reminder) })
                    .help("status_bar_reminders_complete".loco())
                Text(reminder.title.isEmpty ? "status_bar_no_title".loco() : reminder.title)
                    .font(.system(size: metrics.rowFontSize))
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
                title: nextEvent.startDate < clock
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
        moreActionsRow
    }

    // MARK: - More actions

    /// ONE row for the whole utility set. The NSMenu puts these behind a "Quick
    /// Actions" submenu of the Join section; this panel got neither, so once it
    /// became the default dropdown they were reachable only by keyboard shortcut.
    ///
    /// Deliberately one row with a flyout rather than five more rows: the resting
    /// panel keeps exactly one extra line, and everything inside stays one click
    /// away.
    ///
    /// The row is a plain `PanelRow` — the identical path every other action row
    /// takes — so the icon position, the icon/text gutter, the padding, the hover
    /// highlight and the baseline match its neighbours BY CONSTRUCTION rather than
    /// by compensation. A SwiftUI `Menu` is deliberately not used: even with
    /// `.menuStyle(.borderlessButton)` + `.menuIndicator(.hidden)` it wraps its
    /// label in a button container whose intrinsic insets push the icon right and
    /// squeeze the icon/text gutter, leaving the row visibly off the shared grid.
    /// Negative padding cannot reliably cancel that — AppKit applies the insets at
    /// more than one layer and the amounts are not API.
    ///
    /// Instead the tap action calls `openMoreActionsMenu()`, which builds a plain
    /// `NSMenu` — the same AppKit primitive `MenuBuilder`'s Quick Actions submenu
    /// and this view's own `.contextMenu` rows already use — and flies it out from
    /// the row's trailing edge. No layout side-effects, and macOS draws a real
    /// menu, with the keyboard navigation and shortcut display that come free.
    ///
    /// The flyout IS a stock macOS menu; what a submenu gets from AppKit and this
    /// cannot is the parent-side chrome, because that is drawn by `NSMenu` for its
    /// own items and this row is a SwiftUI view, not an `NSMenuItem`. So the row
    /// draws the arrow itself and the popup is positioned to the side. What stays
    /// out of reach is left/right arrow-key traversal between row and flyout —
    /// that would require the whole dropdown to be an `NSMenu` again.
    ///
    /// Not in `DropdownPanelNavigation`'s row list on purpose, so arrow-key travel
    /// still lands only on rows Return completes in a single press. Everything
    /// behind it already has a global shortcut of its own.
    private var moreActionsRow: some View {
        PanelRow(action: { openMoreActionsMenu() }) { _ in
            actionRowContent(
                symbol: "ellipsis.circle",
                title: "dropdown_panel_more_actions".loco(),
                // The submenu arrow AppKit would draw for us if this row were an
                // NSMenuItem. It isn't, so the row draws its own.
                trailingSymbol: "chevron.right"
            )
        }
        .background(MenuAnchorView(box: moreActionsAnchor))
        .onHover { hovering in
            if hovering {
                scheduleMoreActionsMenu()
            } else {
                cancelMoreActionsHover()
            }
        }
    }

    /// Springs the flyout open after a dwell, the way AppKit opens a real submenu.
    /// A click still opens it immediately — `PanelRow`'s tap action goes straight
    /// to `openMoreActionsMenu()` and never consults this.
    @MainActor
    private func scheduleMoreActionsMenu() {
        guard !moreActionsHoverDisarmed else { return }
        moreActionsHoverTimer?.cancel()
        let work = DispatchWorkItem { openMoreActionsMenu() }
        moreActionsHoverTimer = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.moreActionsHoverDelay,
            execute: work
        )
    }

    /// Drops a pending spring-open and re-arms hover for the next entry. Runs when
    /// the pointer leaves the row — including the pass it makes on the way down to
    /// Preferences or Quit, which is why the dwell exists at all.
    @MainActor
    private func cancelMoreActionsHover() {
        moreActionsHoverTimer?.cancel()
        moreActionsHoverTimer = nil
        moreActionsHoverDisarmed = false
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }

    /// The panel's surface.
    ///
    /// On macOS 26 SwiftUI draws it: real Liquid Glass, sampling the desktop
    /// through the clear window. Below that, `PanelBackdrop` supplies an AppKit
    /// `NSVisualEffectView` and this paints nothing.
    ///
    /// Deliberately NOT a hand-built blur. Letting the system own the surface
    /// means it tracks light/dark, accent, reduce-transparency and whatever the
    /// next OS does, none of which a hard-coded translucency would.
    @ViewBuilder
    private var panelSurface: some View {
        if isPreview {
            // Hosted inside the Preferences window, where there is no AppKit
            // backdrop and SwiftUI's own material CAN sample what is behind it
            // (the Preferences window), so it works here and only here.
            panelShape.fill(.regularMaterial)
        } else {
            // `PanelBackdrop`'s NSVisualEffectView is beneath this view, blending
            // against the desktop. Painting here would sit opaquely on top of it.
            Color.clear
        }
    }

    /// A hairline so the panel separates from a light desktop. Glass already
    /// carries its own specular edge, so it needs only a whisper here; flat
    /// material has none and needs the full hairline to avoid bleeding into a
    /// pale wallpaper.
    private var panelEdge: some View {
        // Needed on every version now that the surface is `.menu` vibrancy
        // throughout. The version fork here existed only while macOS 26 used
        // `NSGlassEffectView`, whose specular rim made a second stroke read as a
        // drawn outline.
        //
        // `separatorColor`, not `Color.primary.opacity(...)`. The latter is flat
        // black or flat white depending on appearance, which tinted the rim
        // against the menu material instead of edging it. The semantic colour is
        // the one AppKit uses for exactly this and tracks appearance properly.
        panelShape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
    }

    /// Shows the More-actions flyout beside the row, the way a submenu hangs off
    /// its parent item.
    @MainActor
    private func openMoreActionsMenu() {
        guard let anchor = moreActionsAnchor.view else { return }
        moreActionsHoverTimer?.cancel()
        moreActionsHoverTimer = nil
        // The anchor is flipped, so (width, 0) is its TOP-RIGHT corner: the menu
        // flies out from the panel's trailing edge, level with the row, instead of
        // dropping underneath it. AppKit still flips it to the other side, and
        // slides it vertically, whenever the screen has no room where we asked.
        let menu = makeMoreActionsMenu()
        // Closes the flyout the moment the pointer goes back to the panel, so the
        // rest of the panel is usable again without a dismissing click first.
        let watchdog = MenuExitWatchdog(menu: menu, anchor: anchor)
        watchdog.start()
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: anchor.bounds.width, y: 0),
            in: anchor
        )
        // `popUp` is synchronous — control only lands here once the menu has closed,
        // and the pointer is usually still sitting on the row at that moment. Disarm
        // hover so the flyout does not spring straight back open.
        watchdog.stop()
        moreActionsHoverDisarmed = true
    }

    /// The flyout's contents: the classic Join-section "Quick Actions" submenu
    /// (`MenuBuilder.buildJoinSection`) plus the two entries — camera check and
    /// world clock — that otherwise appear only in the right-click quick-actions
    /// menu. Same gating as those two, so the panel and the classic dropdown can
    /// never disagree about what is *available*. Order is not identical: the
    /// right-click menu lists world clock before camera check; this keeps the
    /// panel's own long-standing camera-then-clock order.
    /// Internal rather than private so `MoreActionsMenuTests` can pin the emitted
    /// item sequence. The gating below is plain conditionals with no other cover.
    @MainActor
    func makeMoreActionsMenu() -> NSMenu {
        let menu = NSMenu(title: "dropdown_panel_more_actions".loco())
        // Each item carries its own enablement. Without this AppKit would grey out
        // every one, since nothing in the responder chain validates them.
        menu.autoenablesItems = false

        if state.nextEvent != nil {
            menu.addItem(ClosureMenuItem(
                title: dismissNextMeetingTitle,
                handler: perform(handlers.dismissNextMeeting)
            ))
        }
        if !state.events.dismissedEvents.isEmpty {
            menu.addItem(ClosureMenuItem(
                title: "status_bar_menu_remove_all_dismissals".loco(),
                handler: perform(handlers.undismissAllMeetings)
            ))
        }
        if state.nextEvent != nil || !state.events.dismissedEvents.isEmpty {
            menu.addItem(.separator())
        }

        let clipboardItem = ClosureMenuItem(
            title: "status_bar_section_join_from_clipboard".loco(),
            handler: perform(handlers.openLinkFromClipboard)
        )
        // Displays the recorded global shortcut without binding a second one — the
        // shortcut is already registered app-wide by `StatusBarItemController`.
        // Matches `MenuBuilder.buildJoinSection`, which sets the same two.
        clipboardItem.setShortcut(for: .openClipboardShortcut)
        menu.addItem(clipboardItem)

        if let titleLabel = meetingTitleVisibilityTitle {
            let toggleItem = ClosureMenuItem(
                title: titleLabel,
                handler: perform(handlers.toggleMeetingTitleVisibility)
            )
            toggleItem.setShortcut(for: .toggleMeetingTitleVisibilityShortcut)
            menu.addItem(toggleItem)
        }
        menu.addItem(.separator())

        // Closes a real parity gap: `MenuBuilder.buildQuickActionsMenu` has offered
        // this for ages, so the calendar window was reachable ONLY by right-clicking
        // the status item. `handlers.openCalendar` was wired end-to-end and simply
        // never called from the panel, which made a whole feature invisible to
        // anyone on the default dropdown.
        menu.addItem(ClosureMenuItem(
            title: "status_bar_quick_action_open_calendar".loco(),
            handler: dismissThen(handlers.openCalendar)
        ))
        menu.addItem(ClosureMenuItem(
            title: "status_bar_quick_action_camera_check".loco(),
            handler: dismissThen(handlers.openCameraPreview)
        ))
        menu.addItem(ClosureMenuItem(
            title: "status_bar_quick_action_world_clock".loco(),
            handler: dismissThen(handlers.openWorldClock)
        ))
        menu.addItem(.separator())

        menu.addItem(ClosureMenuItem(
            title: "status_bar_section_refresh_sources".loco(),
            handler: perform(handlers.refresh)
        ))
        return menu
    }

    /// Mirrors `MenuBuilder.buildJoinSection`: the meeting card's dismiss row
    /// says "current" once the meeting has started.
    private var dismissNextMeetingTitle: String {
        guard let start = state.nextEvent?.startDate, start < clock else {
            return "status_bar_menu_dismiss_next_meeting".loco()
        }
        return "status_bar_menu_dismiss_curent_meeting".loco()
    }

    /// `nil` — i.e. no row — unless the menu bar is actually showing a title to
    /// hide (or a generic one to reveal), exactly as the NSMenu gates it.
    private var meetingTitleVisibilityTitle: String? {
        switch state.statusBar.eventTitleFormat {
        case .show: "status_bar_hide_meeting_names".loco()
        case .generic: "status_bar_show_meeting_names".loco()
        case .dot, .none: nil
        }
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
            actionRowContent(symbol: symbol, title: title)
        }
        .id(row)
    }

    /// `trailingSymbol` is the submenu arrow on a row that opens a flyout. It stays
    /// a parameter of the ONE shared row builder rather than a bespoke layout at
    /// the call site, so a row with an arrow and a row without still get their
    /// icon, text and baseline from exactly the same code.
    @ViewBuilder
    private func actionRowContent(
        symbol: String,
        title: String,
        trailingSymbol: String? = nil
    ) -> some View {
        HStack(spacing: metrics.columnSpacing) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: metrics.actionSymbolWidth)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: metrics.rowFontSize))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let trailingSymbol {
                // `.primary`, not `.secondary`: AppKit draws a submenu arrow in
                // `labelColor` — the same contrast as the item's own text — and
                // only dims it for a DISABLED item. A dimmed arrow on a live row
                // reads as unavailable.
                Image(systemName: trailingSymbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
    }

    /// A small uppercase label, the way the mockup writes a section head.
    ///
    /// The date is appended ONLY when the greeting is not already carrying it.
    /// It used to be unconditional — "Today (Tue, 28 Jul)" — which put the date
    /// in body type in the middle of the list while the greeting, the natural
    /// place for it, said nothing about the day.
    private func sectionHeader(
        _ title: String,
        date: Date? = nil,
        showsCreateAction: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            // 10.5 / .07em / heavy, from the mockup's `.sechead b`. A small
            // uppercase label needs the extra weight and letter-spacing to stay
            // readable — at semibold and 9.5 it read as a faint smudge rather
            // than as a heading.
            Text(sectionHeaderText(title, date: date))
                .font(.system(size: metrics.secondaryFontSize - 1, weight: .bold))
                .textCase(.uppercase)
                .kerning(0.75)
                // `.secondary`, not `.tertiary`. Behind-window vibrancy takes
                // its lightness from the DESKTOP while this colour takes its own
                // from the appearance, so over a pale wallpaper the surface
                // rises to meet a label tuned for a dark one and the heading
                // fades out.
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            if showsCreateAction {
                sectionCreateButton
            }
        }
        .padding(.horizontal, metrics.sectionHeaderInset)
        .padding(.top, 6)
        .padding(.bottom, 3)
    }

    /// Today's heading only, and only where the app can actually write an event.
    ///
    /// "New event" means one starting now-ish, so offering it above tomorrow
    /// would imply it lands there. And in-app creation is EventKit-only —
    /// Google-backed calendars are written through the macOS Calendar app's
    /// sync — so the chip hides for that provider, the same rule the right-click
    /// quick-actions menu applies to its own "New event…" entry.
    private func showsAgendaCreateAction(_ day: AgendaDay) -> Bool {
        day == .today && state.activeProvider == .macOSEventKit
    }

    /// The mockup's `+ ⌘N` chip beside the day's heading — the one action that
    /// belongs next to a list of meetings rather than below it.
    ///
    /// It shows the shortcut because that is the point: the chip is a reminder
    /// that the action has a key, not a new way to reach it. `createMeeting` is
    /// the same handler the action row below runs.
    private var sectionCreateButton: some View {
        HStack(spacing: 3) {
            Image(systemName: "plus")
                .font(.system(size: metrics.secondaryFontSize - 3, weight: .semibold))
            Text("dropdown_panel_new_event_shortcut".loco())
                .font(.system(size: metrics.secondaryFontSize - 2.5, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.primary.opacity(0.12)))
        .overlay(Capsule().strokeBorder(PanelChrome.rim(colorScheme), lineWidth: 0.8))
        .contentShape(Capsule())
        .pointerStyle(.link)
        // `newEvent`, not `createMeeting`. The chip is LABELLED with the ⌘N
        // shortcut, and ⌘N opens the event editor — a chip that advertises a key
        // and then does something else is worse than no chip.
        .onTapGesture(perform: perform(handlers.newEvent))
        .help("status_bar_quick_action_new_event".loco())
    }

    private func sectionHeaderText(_ title: String, date: Date?) -> String {
        guard let date, !greetingShowsDate else { return title }
        return "\(title) (\(sectionDateText(date)))"
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
        DropdownEventVisibility.visible(
            events,
            menu: state.menu,
            display: state.events,
            isDeclined: isDeclined,
            now: clock
        )
    }

    private func eventStartText(_ event: MBEvent) -> String {
        event.isAllDay
            ? "status_bar_event_start_time_all_day".loco()
            : clockText(event.startDate)
    }

    /// `nil` unless `showEventEndTime` is on and the event has a real end time.
    private func eventEndText(_ event: MBEvent) -> String? {
        guard agendaTimeColumn == .startAndEnd, !event.isAllDay else { return nil }
        return clockText(event.endDate)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Read from the environment, not a global: the panel injects the grid for
    /// the user's chosen density, and a row that reached for `.standard` directly
    /// would keep the old rhythm while everything around it changed.
    @Environment(\.dropdownMetrics) private var metrics

    var body: some View {
        content(isHovered)
            .padding(.horizontal, metrics.rowInnerPadding)
            .padding(.vertical, metrics.rowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                PanelHighlight(
                    isSelected: isSelected,
                    isHovered: isHovered && action != nil
                )
            )
            .padding(.horizontal, metrics.rowOuterPadding)
            .contentShape(Rectangle())
            // Scoped pointer style (macOS 15+): unlike NSCursor.push/pop it can't
            // strand a pointing-hand cursor when the panel closes mid-hover.
            // https://developer.apple.com/documentation/swiftui/view/pointerstyle(_:)
            .pointerStyle(action == nil ? nil : .link)
            .onHover { hovering in
                guard action != nil else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
            .onTapGesture { action?() }
    }

}

/// The panel's hover and keyboard-selection surface.
///
/// Neutral glass, NOT an accent fill. A saturated blue bar is the pre-glass
/// look: it paints over the surface instead of lifting a piece of it, and on a
/// translucent panel it reads as a sticker. The demo's row highlight is a lighter
/// pane of the same material — a fill you can see through plus a lit top edge,
/// which is the same vocabulary the cards and buttons use.
///
/// Keyboard selection stays neutral too, but brighter and with an accent-tinted
/// rim. Selection has to be distinguishable from hover (both can be on at once,
/// on different rows), and tinting the EDGE marks it without going back to
/// painting the whole row.
private struct PanelHighlight: View {
    @Environment(\.colorScheme) private var colorScheme

    var isSelected: Bool
    var isHovered: Bool
    var cornerRadius: CGFloat = 7

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(Color.primary.opacity(isSelected ? 0.14 : 0.09))
            .overlay(
                shape.strokeBorder(
                    isSelected
                        ? LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.75),
                                Color.accentColor.opacity(0.18)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        : PanelChrome.rim(colorScheme),
                    lineWidth: 0.8
                )
            )
            .opacity(isSelected || isHovered ? 1 : 0)
    }
}

// MARK: - Card container

/// A bounded surface for a panel component that has its own internal structure.
///
/// The rule this encodes: **card = widget, flat = list.** A timeline or a month
/// grid has its own coordinate system, and a frame tells the eye "parse this as
/// one object". Lists want the opposite — the agenda, the action rows and the
/// footer stay flat so hover targets run full-bleed and the left edge stays
/// unbroken for scanning. A card costs ~24pt of the panel's 330, which a grid can
/// absorb and a truncating event title cannot.
///
/// Deliberately a plain fill, never `glassEffect`, even on macOS 26 where the
/// panel behind it IS glass. Stacked translucency does not compound refraction —
/// it accumulates haze and eats contrast. The panel is the one glass layer; a
/// card sits ON it.
private struct PanelCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    var title: String?
    @ViewBuilder let content: Content

    @Environment(\.dropdownMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                // Matches the agenda's section head — see `sectionHeader`. Two
                // kinds of small uppercase label in one panel would read as an
                // inconsistency rather than a hierarchy.
                Text(title)
                    .font(.system(size: metrics.secondaryFontSize - 1, weight: .bold))
                    .textCase(.uppercase)
                    .kerning(0.65)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(.horizontal, metrics.cardHorizontalPadding)
        .padding(.vertical, metrics.cardVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 0.09, matching the mockup's `rgba(255,255,255,.09)` for a dark glass
        // card. It shipped at 0.06 and read as noticeably flatter — measured
        // against the mockup's CSS rather than adjusted by eye.
        .background(cardShape.fill(Color.primary.opacity(0.09)))
        // A lit rim, not a flat hairline. `Color.primary.opacity(0.06)` drew the
        // same faint line along every edge, which reads as a drawn outline —
        // the pre-glass look. Real glass catches light along its top edge and
        // loses it by the bottom, and that gradient is what gives the card an
        // edge rather than a border. Same treatment as the header buttons, one
        // step softer because a card is a much larger surface.
        .overlay(
            // Floor kept off zero so the lower edge does not vanish: the
            // mockup's border is a uniform 0.16, and a gradient fading to
            // nothing averages well under it.
            cardShape.strokeBorder(PanelChrome.rim(colorScheme, top: 0.20, bottom: 0.08), lineWidth: 1)
        )
        .padding(.horizontal, metrics.rowOuterPadding)
        .padding(.vertical, metrics.cardSpacing)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
    }
}

// MARK: - Layout grid propagation

/// Carries the current density's layout grid down the panel.
///
/// The grid used to be a static on each view, which meant every row silently
/// agreed on `.standard`. Once density became a preference that stopped being
/// true, and a static would have left nested rows on the old rhythm while their
/// container moved. The environment is the mechanism that guarantees one panel
/// renders with exactly one grid.
private struct DropdownMetricsKey: EnvironmentKey {
    /// Only reached by a view rendered outside the panel (a `#Preview`, say).
    /// Inside the panel the value is always injected.
    static let defaultValue = DropdownMetrics.standard
}

extension EnvironmentValues {
    var dropdownMetrics: DropdownMetrics {
        get { self[DropdownMetricsKey.self] }
        set { self[DropdownMetricsKey.self] = newValue }
    }
}

// MARK: - AppKit menu plumbing

/// An `NSMenuItem` that runs a Swift closure.
///
/// AppKit menu items are target/action only, and every other item in this app
/// points at an `@objc` selector on `StatusBarItemController`. The panel has no
/// such controller — its actions arrive as closures on `DropdownPanelHandlers` —
/// so this is the shim that lets the More-actions flyout reuse them verbatim
/// instead of duplicating each one as a new selector.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        // `NSMenuItem.target` is weak, so self-targeting is not a retain cycle;
        // the menu keeps the item alive for as long as it is on screen.
        target = self
        isEnabled = true
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("ClosureMenuItem is built in code, never from a nib")
    }

    @objc private func run() {
        // Gets the handler off THIS AppKit callback's stack. Most of these handlers
        // close the panel, and the anchor view the menu was positioned against
        // lives inside it — the same shape of reentrancy
        // `DropdownPanelWindow.resignKey()` defers for, having once crashed on it.
        // Note this buys stack separation, not ordering: the main queue is drained
        // in event-tracking mode too, so the block may still run while the menu is
        // finishing up. Stack separation is the part that matters here.
        let handler = handler
        DispatchQueue.main.async { handler() }
    }
}

/// Closes an open `NSMenu` as soon as the pointer returns to the panel behind it.
///
/// `NSMenu.popUp` runs a modal tracking session: while the flyout is up, the panel
/// receives no mouse events at all, so a SwiftUI `.onHover` cannot notice the
/// pointer coming back and every other row sits dead until a dismissing click. A
/// real submenu closes when you move to a sibling item; this restores that by
/// polling the pointer and cancelling tracking once it is over the panel again.
///
/// "Over the panel" is decided with `NSWindow.windowNumber(at:below:)` rather than
/// a frame-containment test, because AppKit flips the flyout to the panel's other
/// side whenever the screen edge is close — which it often is, the panel hanging
/// off a status item near the right of the menu bar. A frame test would then read
/// the flyout's own area as "inside the panel" and shut it the instant it opened.
/// Asking which window is actually frontmost at that point cannot be fooled by
/// where the menu landed.
@MainActor
private final class MenuExitWatchdog {
    private let menu: NSMenu
    private weak var anchor: NSView?
    private var timer: Timer?

    /// Fast enough to feel like the menu reacts to the pointer, coarse enough to
    /// stay invisible next to the 0.25s dwell that opened it.
    private static let interval: TimeInterval = 0.05

    init(menu: NSMenu, anchor: NSView) {
        self.menu = menu
        self.anchor = anchor
    }

    func start() {
        let timer = Timer(timeInterval: Self.interval, repeats: true) { _ in
            MainActor.assumeIsolated { self.tick() }
        }
        // `.common` so it keeps firing inside the menu's own event-tracking mode;
        // a plain scheduled timer runs in `.default` only and would stall for the
        // entire life of the menu — exactly when it needs to be running.
        RunLoop.current.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let anchor, let panel = anchor.window else { return }
        let pointer = NSEvent.mouseLocation
        // Still on the row that owns the flyout: a real submenu stays open here.
        let rowOnScreen = panel.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        guard !rowOnScreen.contains(pointer) else { return }
        // Frontmost window under the pointer is the panel, so the pointer is NOT on
        // the flyout (which draws above it) and not on another app either.
        guard NSWindow.windowNumber(at: pointer, belowWindowWithWindowNumber: 0)
            == panel.windowNumber else { return }
        menu.cancelTracking()
    }
}

/// Carries the AppKit view the More-actions `NSMenu` anchors to.
///
/// `NSMenu.popUp(positioning:at:in:)` needs a real `NSView` to hang from and
/// SwiftUI has none to hand out, so `MenuAnchorView` parks one in the row and
/// reports it back through this box. Held weakly: the view belongs to the panel's
/// hosting hierarchy, which outlives no menu.
private final class MenuAnchorBox {
    weak var view: NSView?
}

/// A zero-size, non-interactive AppKit view whose only job is to be somewhere for
/// a native menu to hang from.
private struct MenuAnchorView: NSViewRepresentable {
    let box: MenuAnchorBox

    func makeNSView(context _: Context) -> NSView {
        let view = FlippedAnchor()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        // The panel rebuilds this struct on every clock tick; re-point the box so
        // it can never be left holding a view from a torn-down hierarchy.
        box.view = nsView
    }

    /// Flipped so callers can read `bounds.height` as the row's BOTTOM edge.
    private final class FlippedAnchor: NSView {
        override var isFlipped: Bool { true }

        /// Never take a click — the `PanelRow` in front of it owns the hit area.
        override func hitTest(_: NSPoint) -> NSView? { nil }
    }
}

#Preview {
    DropdownPanelView(state: StatusBarMenuState(), handlers: DropdownPanelHandlers())
}
