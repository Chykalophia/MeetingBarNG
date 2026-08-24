//
//  StatusBarItemController.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
//  Modified for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026:
//  render the status-bar title through the composable menu-bar presenter when
//  the user has set a custom token composition, and observe its Defaults keys;
//  assemble the dropdown from the composable-dropdown block-join (toggleable +
//  reorderable modules, with the enabled-module set resolved through the shared
//  DropdownCompositionPolicy.enabledRawValues helper so the Display-tab live
//  preview and the real menu can never drift); remove the "Rate App" action that
//  opened the original
//  App Store listing; add an "Open calendar" entry point (dependency closure,
//  keyboard shortcut, and @objc handler) for the month calendar window; add the
//  in-app event editor entry points (new/edit/delete dependency closures, the
//  .newEventShortcut registration, and @objc handlers, with a destructive NSAlert
//  before delete); add the camera/mic pre-call preview entry points (the
//  openCameraPreview dependency closure, the .cameraPreviewShortcut registration,
//  and the standalone/per-event @objc handlers); add a "World clock" entry point
//  (the openWorldClock dependency closure, the .worldClockShortcut registration,
//  and the @objc handler) for the multi-zone world-clock panel window; kick a
//  debounced aggressive calendar force-sync (.forceCalendarSync) whenever the
//  dropdown is about to show, so a stalled macOS Calendar sync surfaces (and
//  self-corrects) on open; route a left-click to the SwiftUI dropdown panel
//  (openDropdownPanel dependency + handlers); split each per-event / per-reminder
//  @objc action into a
//  thin sender-unwrapping wrapper over a value-taking method (editEvent,
//  confirmAndDeleteEvent, copyDetail, copyMeetingLink, openReferenceURL,
//  emailAttendees, undismiss, completeReminder, snoozeReminder,
//  openReminderInApp) so the SwiftUI panel's handlers run the SAME code path as
//  the NSMenu items rather than a reimplementation; wire the panel's "More
//  actions" menu (open link from clipboard, toggle the menu-bar meeting title,
//  camera check, world clock, dismiss / remove all dismissals) to those same
//  @objc handlers, since the panel became the default dropdown and the NSMenu's
//  quick-actions subsection had no counterpart there. Add the menu bar's Join
//  chip: draw its capsule as an overlay on the status-item button, and route a
//  left-click inside that capsule to joinNextMeeting() instead of to the
//  dropdown.
//

import Cocoa
import Combine
import Defaults
import KeyboardShortcuts

enum MenuStyleConstants {
    static let defaultFontSize: CGFloat = 13
    static let runningIconName = "running_icon"
    static let appIconName = "AppIcon"
    static let calendarCheckmarkIconName = "iconCalendarCheckmark"
    static let calendarIconName = "iconCalendar"
    static let iconSize: NSSize = .init(width: 16, height: 16)

    /// Loads a named asset; if the asset is missing or has been renamed,
    /// falls back to the bundle's runtime app icon and finally to a 1x1
    /// placeholder so the menu bar never crashes on a misconfigured Defaults
    /// value or a renamed asset.
    static func iconNamed(_ name: String) -> NSImage {
        if let image = NSImage(named: name) {
            return image
        }
        if let appIcon = NSImage(named: NSImage.applicationIconName) {
            return appIcon
        }
        return NSImage(size: NSSize(width: 1, height: 1))
    }
}

struct StatusBarDependencies {
    var appState: @MainActor () -> AppState = { AppState() }
    var events: @MainActor () -> [MBEvent] = { [] }
    var send: @MainActor (AppAction) -> Void = { _ in }
    var openPreferences: @MainActor () -> Void = {}
    var openChangelog: @MainActor () -> Void = {}
    var openCommandBar: @MainActor () -> Void = {}
    /// Opens (or toggles) the SwiftUI dropdown panel below the status
    /// item. Receives a fresh menu-state snapshot, the panel's handlers, and the
    /// status-item button's rect in screen coordinates.
    var openDropdownPanel: @MainActor (StatusBarMenuState, DropdownPanelHandlers, NSRect) -> Void =
        { _, _, _ in }
    var openCalendar: @MainActor () -> Void = {}
    var openWorldClock: @MainActor () -> Void = {}
    var openCameraPreview: @MainActor (MBEvent?) -> Void = { _ in }
    var newEvent: @MainActor () -> Void = {}
    /// Events in `[from, to)` — the same closure the calendar window is given, so
    /// the panel's month dots and the window's grid ask one question.
    var fetchEvents: @MainActor (_ from: Date, _ to: Date) async throws -> [MBEvent] =
        { _, _ in [] }
    var editEvent: @MainActor (MBEvent) -> Void = { _ in }
    var deleteEvent: @MainActor (MBEvent, EventEditSpan) -> Void = { _, _ in }
    var quit: @MainActor () -> Void = {}
    #if DEBUG
    /// Opens the development harness. Guarded so the release build's dependency
    /// struct has no member for a tool that does not exist in it.
    var openDebugHarness: @MainActor () -> Void = {}
    #endif
}

/// creates the menu in the system status bar, creates the menu items and controls the whole lifecycle.
@MainActor
final class StatusBarItemController {
    var statusItem: NSStatusItem!

    /// The menu-bar progress indicator, added to the status-item button once and
    /// reused. Held weakly: the button owns it as a subview, and a strong ref
    /// here would outlive a status item that got torn down and rebuilt.
    private weak var meetingProgressOverlay: MeetingProgressOverlayView?

    /// The Join chip's capsule, added and held on the same terms.
    private weak var actionChipOverlay: MenuBarActionChipOverlayView?

    /// Where a left-click means "join" rather than "open the panel", in the
    /// status-item button's coordinates. `nil` whenever no chip is drawn — which
    /// is what keeps the click behaviour identical to before whenever the feature
    /// is off, the meeting is not close yet, or it has nothing to join.
    ///
    /// Readable (not settable) outside the controller so a test can assert the
    /// click target actually lands on a real status item, which is the half of
    /// this the pure geometry tests cannot reach.
    private(set) var actionChipHitRect: CGRect?

    /// Current event list, driven by the AppModel state.
    /// A non-nil `_eventsOverride` takes precedence (used by tests to inject
    /// events without wiring up the full app model chain).
    private var _eventsOverride: [MBEvent]?
    var events: [MBEvent] {
        get { _eventsOverride ?? dependencies.events() }
        set { _eventsOverride = newValue }
    }

    let installationDate = getInstallationDate()

    private var dependencies = StatusBarDependencies()

    private var cancellables = Set<AnyCancellable>()

    /// One-shot redraw timer, re-armed on every `updateTitle()`. See
    /// `scheduleNextTick(now:event:)` — this is the app's only UI clock.
    private var tickTimer: Timer?

    /// Removes the status item from the system status bar and tears down the
    /// timer. Called from `AppDelegate.applicationWillTerminate` so the item
    /// doesn't linger as a stale icon when the process is killed — a common
    /// annoyance during local dev rebuilds where each run leaves a frozen
    /// status item at whatever icon its state was in.
    func removeFromStatusBar() {
        tickTimer?.invalidate()
        tickTimer = nil
        cancellables.removeAll()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    init() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusMenuBarAction)
        statusItem.button?.sendAction(on: [
            NSEvent.EventTypeMask.rightMouseDown, NSEvent.EventTypeMask.leftMouseUp,
            NSEvent.EventTypeMask.leftMouseDown
        ])

        // Temporary icon before app delegate setup
        statusItem.button?.image = MenuStyleConstants.iconNamed(MenuStyleConstants.appIconName)
        statusItem.button?.image?.size = MenuStyleConstants.iconSize
        statusItem.button?.imagePosition = .imageLeft

        setupDefaultsObservers()
        setupKeyboardShortcuts()
    }

    private func setupDefaultsObservers() {
        // For all these keys, just redraw:
        Defaults.publisher(
            keys: .statusbarEventTitleLength, .eventTimeFormat,
            .eventTitleIconFormat, .showEventMaxTimeUntilEventThreshold,
            .showEventMaxTimeUntilEventEnabled, .showEventDetails,
            .menuBarHighlightImminentEvent, .eventActionHighlightMinutes,
            .shortenEventTitle, .menuEventTitleLength,
            .showEventEndTime, .showMeetingServiceIcon,
            .showEventCalendarColor, .showMeetingPrepLinks,
            .timeFormat, .bookmarks, .deduplicateEvents,
            .personalEventsAppereance, .pastEventsAppereance,
            .declinedEventsAppereance, .ongoingEventVisibility,
            .showTimelineInMenu, .hideFinishedEventsInMenu,
            .menuBarTokens, .menuBarCountdownStyle, .menuBarDateStyle,
            .menuBarProgressStyle, .menuBarWorldClockTimeZone, .menuBarWorldClockLabel,
            .menuBarTwoLineLayout,
            .menuBarShowJoinAction, .menuBarJoinActionLeadMinutes,
            .menuBarCountdownLeadMinutes,
            .showGreetingInMenu, .greetingName,
            .showRemindersInMenu, .remindersIncludeOverdue,
            .dropdownModuleOrder, .showMeetingControlInMenu,
            .showAgendaInMenu, .showJoinSectionInMenu, .showBookmarksInMenu,
            options: []
        )
        // Only the title needs redrawing on a settings change now. The dropdown
        // builds its whole state fresh every time it opens, so there is nothing
        // to keep in sync between opens — that was an NSMenu requirement, since a
        // menu is a long-lived object you mutate in place.
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.updateTitle()
        }
        .store(in: &cancellables)

        Defaults.publisher(.eventTitleFormat, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateTitle()
                self?.reconcileNotifications()
            }
            .store(in: &cancellables)

        Defaults.publisher(.preferredLanguage, options: [.initial])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                if I18N.instance.changeLanguage(to: change.newValue) {
                    self?.updateTitle()
                    self?.reconcileNotifications()
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(
            keys: .joinEventNotification,
            .joinEventNotificationTime,
            .endOfEventNotification,
            .endOfEventNotificationTime,
            .fullscreenNotification,
            .fullscreenNotificationTime,
            .fullscreenNotificationsForEventsWithoutMeetingLink,
            .automaticEventJoin,
            .automaticEventJoinTime,
            .runEventStartScript,
            .eventStartScriptTime,
            .eventStartScriptLocation,
            .dismissedEvents,
            options: []
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.reconcileNotifications()
        }
        .store(in: &cancellables)
    }

    private func reconcileNotifications() {
        dependencies.send(.reconcileNotifications)
    }

    private func setupKeyboardShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .createMeetingShortcut, action: createMeeting)

        KeyboardShortcuts.onKeyUp(for: .joinEventShortcut) {
            Task { @MainActor in self.joinNextMeeting() }
        }

        KeyboardShortcuts.onKeyUp(for: .openMenuShortcut) {
            Task { @MainActor in self.toggleDropdownPanel() }
        }

        KeyboardShortcuts.onKeyUp(for: .openClipboardShortcut, action: openLinkFromClipboard)

        KeyboardShortcuts.onKeyUp(for: .toggleMeetingTitleVisibilityShortcut) {
            Task { @MainActor in self.dependencies.send(.toggleMeetingTitleVisibility) }
        }

        KeyboardShortcuts.onKeyUp(for: .commandBarShortcut) {
            Task { @MainActor in self.dependencies.openCommandBar() }
        }

        KeyboardShortcuts.onKeyUp(for: .calendarShortcut) {
            Task { @MainActor in self.dependencies.openCalendar() }
        }

        KeyboardShortcuts.onKeyUp(for: .worldClockShortcut) {
            Task { @MainActor in self.dependencies.openWorldClock() }
        }

        KeyboardShortcuts.onKeyUp(for: .cameraPreviewShortcut) {
            Task { @MainActor in self.dependencies.openCameraPreview(nil) }
        }

        KeyboardShortcuts.onKeyUp(for: .newEventShortcut) {
            Task { @MainActor in self.dependencies.newEvent() }
        }
    }

    @objc
    func statusMenuBarAction(sender _: NSStatusItem) {
        let event = NSApp.currentEvent

        if event?.type == .rightMouseUp {
            // Right button click → compact quick-actions menu. Still an NSMenu,
            // and rightly so: it is a short list of verbs, which is exactly what
            // a menu is for.
            showQuickActionsMenu()
            return
        }
        guard event == nil || event?.type == .leftMouseDown || event?.type == .leftMouseUp else {
            return
        }
        // The status-item button sends its action on BOTH left-mouse-down and
        // left-mouse-up, and the panel sees both, so a single click would toggle
        // it twice. Act on the down edge (and on the shortcut's synthetic nil
        // event) only.
        guard event?.type != .leftMouseUp else { return }

        // The Join chip is drawn INTO the item's title, not added as a control:
        // a status item is one button, and its click opens the panel. So the
        // chip's rect is tested here instead. The same rect the overlay drew, so
        // the target cannot drift from the capsule the user is aiming at.
        if let event, isActionChipClick(event) {
            joinNextMeeting()
            return
        }
        toggleDropdownPanel()
    }

    /// Whether `event` landed on the Join chip.
    private func isActionChipClick(_ event: NSEvent) -> Bool {
        guard let hitRect = actionChipHitRect,
              let button = statusItem?.button,
              button.window != nil
        else { return false }
        // Modified clicks stay the panel's: ⌥-click and friends are how the rest
        // of the app reaches alternates, and joining on one would be a surprise.
        guard event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask) else {
            return false
        }
        return hitRect.contains(button.convert(event.locationInWindow, from: nil))
    }

    /// Opens (or closes, when already open) the SwiftUI dropdown panel with a
    /// freshly built state snapshot — the same snapshot `updateMenu()` renders
    /// the NSMenu from — anchored to the status-item button.
    func toggleDropdownPanel() {
        nudgeCalendarForceSync()

        var appState = dependencies.appState()
        appState.events = events
        let menuState = StatusBarMenuState.make(from: appState)

        guard let statusItem, let button = statusItem.button, let window = button.window else {
            MeetingBarLogger.lifecycle.error(
                "SwiftUI dropdown panel: status-item button has no window; skipping"
            )
            return
        }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        dependencies.openDropdownPanel(menuState, dropdownPanelHandlers(), anchor)
    }

    #if DEBUG
    /// Everything `toggleDropdownPanel` would hand the panel, for the DEBUG
    /// inspector window to host instead.
    ///
    /// Built from the same three lines rather than a copy, so the inspector shows
    /// the real snapshot — including whatever `nudgeCalendarForceSync` pulls in.
    /// `anchor` is `nil` when the status item has no window yet; the inspector
    /// falls back to a synthetic one rather than refusing to open, since being
    /// inspectable without a live status item is half the point.
    func dropdownPanelSnapshotForInspector() -> DropdownInspectorSnapshot {
        nudgeCalendarForceSync()

        var appState = dependencies.appState()
        appState.events = events
        let menuState = StatusBarMenuState.make(from: appState)

        let anchor = statusItem?.button.flatMap { button in
            button.window.map { $0.convertToScreen(button.convert(button.bounds, to: nil)) }
        }
        return DropdownInspectorSnapshot(
            state: menuState,
            handlers: dropdownPanelHandlers(),
            anchor: anchor
        )
    }
    #endif

    /// The panel's side effects, routed through the same dependency closures the
    /// same @objc handlers the right-click quick-actions menu targets, so the two
    /// surfaces share one behavior surface. `dismiss` is filled in by the host.
    private func dropdownPanelHandlers() -> DropdownPanelHandlers {
        DropdownPanelHandlers(
            joinEvent: { [weak self] event in
                self?.dependencies.send(.joinMeeting(eventID: event.id))
            },
            openBookmark: { bookmark in
                MeetingOpener.open(
                    meetingLink: MeetingLink(
                        service: MeetingServices(rawValue: bookmark.service),
                        url: bookmark.url
                    )
                )
            },
            createMeeting: { createMeeting() },
            newEvent: { [weak self] in self?.dependencies.newEvent() },
            fetchEvents: { [weak self] from, to in
                guard let self else { return [] }
                return try await self.dependencies.fetchEvents(from, to)
            },
            refresh: { [weak self] in self?.dependencies.send(.refreshCalendars) },
            openPreferences: { [weak self] in self?.dependencies.openPreferences() },
            openCalendar: { [weak self] in self?.dependencies.openCalendar() },
            openCommandBar: { [weak self] in self?.dependencies.openCommandBar() },
            openChangelog: { [weak self] in self?.dependencies.openChangelog() },
            quit: { [weak self] in self?.dependencies.quit() },
            // The panel's "More actions" menu. Each of these runs the SAME @objc
            // handler the NSMenu's quick-actions items target, so restoring them
            // in the panel reimplements nothing.
            openLinkFromClipboard: { [weak self] in self?.openLinkFromClipboardAction() },
            toggleMeetingTitleVisibility: { [weak self] in self?.toggleMeetingTitleVisibility() },
            openCameraPreview: { [weak self] in self?.openCameraPreviewAction() },
            openWorldClock: { [weak self] in self?.openWorldClockAction() },
            dismissNextMeeting: { [weak self] in self?.dismissNextMeetingAction() },
            undismissAllMeetings: { [weak self] in self?.undismissMeetingsActions() },
            editEvent: { [weak self] event in self?.editEvent(event) },
            deleteEvent: { [weak self] event in self?.confirmAndDeleteEvent(event) },
            copyText: { [weak self] value in self?.copyDetail(value) },
            copyMeetingLink: { [weak self] event in self?.copyMeetingLink(for: event) },
            copyMeetingIdentifier: { [weak self] event in self?.copyMeetingIdentifier(for: event) },
            openURL: { [weak self] url in self?.openReferenceURL(url) },
            emailAttendees: { [weak self] event in self?.emailAttendees(for: event) },
            dismissEvent: { [weak self] event in self?.dismiss(event: event) },
            undismissEvent: { [weak self] event in self?.undismiss(event: event) },
            completeReminder: { [weak self] reminder in self?.completeReminder(reminder) },
            snoozeReminder: { [weak self] reminder, option in
                self?.snoozeReminder(reminder, option: option)
            },
            openReminderInApp: { [weak self] reminder in self?.openReminderInApp(reminder) }
        )
    }

    /// Opening the dropdown is a strong "the user wants current data now" signal, so
    /// proactively nudge macOS to sync (EventKit `refreshSourcesIfNecessary()`)
    /// via `CalendarSync`. Debounced there (~30s) so repeated menu-opens don't
    /// hammer EventKit.
    private func nudgeCalendarForceSync() {
        dependencies.send(.forceCalendarSync)
    }

    /// Pops up the right-click quick-actions menu at the status item.
    func showQuickActionsMenu() {
        nudgeCalendarForceSync()
        guard let statusItem else { return }
        var appState = dependencies.appState()
        appState.events = events
        let menuState = StatusBarMenuState.make(from: appState)
        let menu = QuickActionsMenu.build(target: self, state: menuState)
        #if DEBUG
        // Appended here rather than inside `QuickActionsMenu.build`, so the
        // shipping menu builder never carries a case for a development tool.
        menu.addItem(.separator())
        let harness = NSMenuItem(
            title: "Debug harness…",
            action: #selector(openDebugHarnessAction),
            keyEquivalent: ""
        )
        harness.target = self
        menu.addItem(harness)
        #endif
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// Copies today's agenda to the pasteboard (same text the Command Bar's
    /// "Copy agenda" produces), reachable without a shortcut via right-click.
    @objc func copyTodayAgendaAction() {
        let now = Date()
        let calendar = Calendar.current
        let todays = events
            .filter { calendar.isDate($0.startDate, inSameDayAs: now) }
            .sorted { $0.startDate < $1.startDate }
        let entries = todays.map { event in
            CommandBarAgendaEntry(
                title: event.title,
                timeRange: event.isAllDay ? "" : agendaTimeRange(event),
                isAllDay: event.isAllDay
            )
        }
        let header = "command_bar_agenda_header".loco(agendaDateText(now, calendar: calendar))
        let text = CommandBarAgenda.text(
            for: entries,
            header: header,
            emptyPlaceholder: "command_bar_agenda_empty".loco()
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func agendaTimeRange(_ event: MBEvent) -> String {
        "\(agendaClock(event.startDate)) – \(agendaClock(event.endDate))"
    }

    private func agendaClock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = I18N.instance.locale
        formatter.setLocalizedDateFormatFromTemplate(Defaults[.timeFormat] == .military ? "Hmm" : "hmma")
        return formatter.string(from: date)
    }

    private func agendaDateText(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = I18N.instance.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return formatter.string(from: date)
    }

    func configure(dependencies: StatusBarDependencies) {
        self.dependencies = dependencies
    }

    func updateTitle() {
        let now = Date()
        let selectedEvent = events.nextEvent()
        let nextEvent = selectedEvent.map(StatusBarEventPresentationInput.init)
        // Re-arm the clock against whatever meeting is now current. Doing it
        // here (rather than only on a fixed interval) means the redraw lands
        // exactly on the next state change, and re-arms itself whenever the
        // calendar, the settings, or the selected meeting change.
        scheduleNextTick(now: now, event: selectedEvent)

        let presentation: StatusBarPresentation
        if let composition = MenuBarComposition.currentIfEnabled {
            // User opted into a custom token layout (composable menu bar).
            presentation = StatusBarPresenter.composedPresentation(
                nextEvent: nextEvent,
                composition: composition,
                settings: .current,
                now: now,
                calendar: statusBarCalendar()
            )
        } else {
            // Classic path — byte-for-byte unchanged for existing installs.
            presentation = StatusBarPresenter.presentation(
                nextEvent: nextEvent,
                settings: .current,
                now: now,
                calendar: statusBarCalendar()
            )
        }

        if presentation.removeDeliveredNotifications, Defaults[.joinEventNotification] {
            removeDeliveredNotifications()
        }

        renderStatusBar(presentation)
    }

    // MARK: - The clock

    /// Re-arms the redraw timer for the next instant at which the menu bar's
    /// contents change *because time passed* — a meeting starting or ending,
    /// the "hide the current meeting N minutes after it starts" point, or
    /// simply the next minute so a countdown stays honest.
    ///
    /// Before this existed the app had no clock: redraws were a side effect of
    /// a Defaults change or of the 180-second calendar poll, so a meeting could
    /// begin and the menu bar would keep showing the previous one for minutes.
    /// One-shot and re-armed on every redraw, so it always targets the *current*
    /// next meeting and never accumulates timers.
    private func scheduleNextTick(now: Date, event: MBEvent?) {
        tickTimer?.invalidate()

        var transitions = StatusBarTickPolicy.transitionDates(
            eventStart: event?.startDate,
            eventEnd: event?.endDate,
            ongoingGracePeriod: Defaults[.ongoingEventVisibility].gracePeriod
        )
        // The instant the Join chip is due. The minute boundary would show it
        // within 60 seconds anyway; this is what makes a meeting starting at
        // 10:00:30 get its full two minutes rather than one and a half.
        if let start = event?.startDate {
            if let due = MenuBarJoinActionPolicy.appearanceDate(
                eventStart: start,
                settings: .current
            ) {
                transitions.append(due)
            }
            // Same reasoning for the countdown block's own lead time.
            if let due = MenuBarCompositionPolicy.countdownAppearanceDate(
                eventStart: start,
                leadMinutes: Defaults[.menuBarCountdownLeadMinutes]
            ) {
                transitions.append(due)
            }
        }

        let fireDate = StatusBarTickPolicy.nextFireDate(
            now: now,
            transitions: transitions,
            calendar: statusBarCalendar()
        )

        let timer = Timer(
            timeInterval: StatusBarTickPolicy.delay(now: now, until: fireDate),
            repeats: false
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.updateTitle() }
        }
        // .common so the countdown keeps advancing while a menu is tracking or
        // a window is being resized, which .default would stall.
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    func renderStatusBar(_ presentation: StatusBarPresentation) {
        guard let statusItem, let button = statusItem.button else { return }

        button.image = nil
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.toolTip = nil
        button.alignment = .center
        button.cell?.lineBreakMode = .byTruncatingTail

        switch presentation.icon {
        case .asset(let name):
            button.image = MenuStyleConstants.iconNamed(name)
            button.image?.size = MenuStyleConstants.iconSize
        case .meetingService(let service):
            button.image = getIconForMeetingService(service)
        case .none:
            break
        }
        if button.image?.name() == "no_online_session" {
            button.imagePosition = .noImage
        } else {
            button.imagePosition = presentation.iconPosition == .trailing ? .imageRight : .imageLeft
        }

        // Render the composed title whenever there is one (event mode, or a
        // non-event clock/date composition). `.none` layout ⇒ icon-only.
        if presentation.layout != .none {
            button.attributedTitle = StatusBarTitleRenderer.attributedTitle(for: presentation)
        }
        if let tooltip = presentation.tooltip {
            button.toolTip = tooltip
        }

        ensureStatusBarButtonIsVisible(button)
        renderMeetingProgress(on: button)
        // Last: the chip is measured against the button's FINAL image and title,
        // and `renderMeetingProgress` can still claim the image slot above.
        renderActionChip(on: button, presentation: presentation)

        #if DEBUG
        lastRenderedPresentation = presentation
        #endif
    }

    #if DEBUG
    @objc
    func openDebugHarnessAction() {
        dependencies.openDebugHarness()
    }

    /// The last presentation drawn, for the debug harness's readout. Kept behind
    /// the flag so the release build does not retain a presentation nothing reads.
    private var lastRenderedPresentation: StatusBarPresentation?

    /// Replaces the event list with synthetic ones, or clears back to the real
    /// calendar when handed `nil`.
    ///
    /// The `events` setter cannot express "stop overriding" — it takes a
    /// non-optional array — so the harness needs this rather than the public
    /// seam. Redraws immediately so a click in the harness moves the menu bar
    /// without waiting for the next tick.
    func debugOverrideEvents(_ events: [MBEvent]?) {
        _eventsOverride = events
        updateTitle()
    }

    /// What the menu bar is currently drawing, for the harness's readout.
    func debugRenderSummary() -> DebugRenderSummary {
        DebugRenderSummary(
            firstLine: lastRenderedPresentation?.title ?? "",
            secondLine: lastRenderedPresentation?.time ?? "",
            actionLabel: lastRenderedPresentation?.actionLabel ?? "",
            chipRect: actionChipHitRect,
            buttonWidth: statusItem?.button?.bounds.width ?? 0,
            eventCount: events.count,
            isOverridden: _eventsOverride != nil,
            hasSelectedCalendars: !Defaults[.selectedCalendarIDs].isEmpty
        )
    }
    #endif

    // MARK: - Join chip (menu bar)

    /// Positions the Join chip's capsule and its click target, or clears both.
    ///
    /// The chip is the trailing run of the string AppKit just laid out, which is
    /// the whole trick: measuring that run gives its width, and the presenter
    /// guarantees it is last (`composedLines`), so nothing has to be re-laid-out
    /// to find it.
    private func renderActionChip(on button: NSStatusBarButton, presentation: StatusBarPresentation) {
        let label = presentation.actionLabel
        let title = button.attributedTitle
        let labelLength = label.utf16.count

        guard !label.isEmpty, title.length >= labelLength, labelLength > 0 else {
            clearActionChip()
            return
        }

        // Verify the trailing run really is the label. Belt and braces: if the
        // renderer ever appends something after the chip, this drops the chip
        // rather than putting a live click target over the wrong glyphs.
        let range = NSRange(location: title.length - labelLength, length: labelLength)
        let trailing = title.attributedSubstring(from: range)
        guard trailing.string == label else {
            clearActionChip()
            return
        }

        let isStacked = presentation.layout == .stacked
        let lastLine = isStacked
            ? title.attributedSubstring(from: lastLineRange(of: title))
            : title
        let hasImage = button.imagePosition != .noImage && button.image != nil

        guard let chip = MenuBarActionChipGeometry.rect(
            MenuBarActionChipMetrics(
                buttonBounds: button.bounds,
                imageWidth: hasImage ? (button.image?.size.width ?? 0) : 0,
                imageIsTrailing: button.imagePosition == .imageRight,
                titleWidth: renderedWidth(of: title),
                lineWidth: renderedWidth(of: lastLine),
                labelWidth: renderedWidth(of: trailing),
                isStacked: isStacked
            )
        ) else {
            clearActionChip()
            return
        }

        let overlay = actionChipOverlay ?? {
            let view = MenuBarActionChipOverlayView()
            view.autoresizingMask = [.width, .height]
            button.addSubview(view)
            actionChipOverlay = view
            return view
        }()
        overlay.frame = button.bounds
        overlay.chipRect = chip

        actionChipHitRect = MenuBarActionChipGeometry.hitRect(chip: chip, buttonBounds: button.bounds)
    }

    private func clearActionChip() {
        actionChipOverlay?.chipRect = nil
        actionChipHitRect = nil
    }

    /// Width of the widest line, so a two-line title measures as it draws.
    /// `NSAttributedString.size()` does not wrap, and treats the newline as part
    /// of one long run.
    private func renderedWidth(of string: NSAttributedString) -> CGFloat {
        guard string.length > 0 else { return 0 }
        return ceil(
            string.boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).width
        )
    }

    /// The range of the text after the last newline — the stack's detail line,
    /// which is the one the chip rides.
    private func lastLineRange(of string: NSAttributedString) -> NSRange {
        let text = string.string as NSString
        let newline = text.rangeOfCharacter(from: .newlines, options: .backwards)
        guard newline.location != NSNotFound else {
            return NSRange(location: 0, length: string.length)
        }
        let start = newline.location + newline.length
        return NSRange(location: start, length: string.length - start)
    }

    // MARK: - Meeting progress (menu bar)

    /// Draws (or clears) the menu-bar progress indicator for the next meeting.
    ///
    /// Runs after the rest of the item is in place, because two of the styles are
    /// sized from the button's final bounds and the ring needs the icon that was
    /// just assigned.
    private func renderMeetingProgress(on button: NSStatusBarButton) {
        let style = MeetingProgressStyle(rawValue: Defaults[.meetingProgressStyle]) ?? .none
        let progress = style.drawsSomething ? currentMeetingProgress() : nil

        guard let progress else {
            meetingProgressOverlay?.presentation = nil
            return
        }

        if style.occupiesImageSlot {
            // The bar takes the image slot outright. Documented as the one style
            // that costs menu-bar width — it is not an overlay, so it cannot
            // share the space with an icon.
            button.image = MeetingProgressRenderer.barImage(for: progress)
            button.imagePosition = .imageLeft
            meetingProgressOverlay?.presentation = nil
            return
        }

        // A ring needs something to sit around. With no icon in the item — the
        // title-only compositions, which are common — an overlay ring lands on
        // the first letter of the title instead, so it takes the image slot and
        // becomes the icon.
        if style == .ring, button.image == nil {
            button.image = MeetingProgressRenderer.ringImage(for: progress)
            button.imagePosition = .imageLeft
            meetingProgressOverlay?.presentation = nil
            return
        }

        let overlay = meetingProgressOverlay ?? {
            let view = MeetingProgressOverlayView()
            view.autoresizingMask = [.width, .height]
            button.addSubview(view)
            meetingProgressOverlay = view
            return view
        }()
        overlay.frame = button.bounds
        overlay.iconWidth = button.image?.size.width ?? 0
        overlay.style = style
        overlay.presentation = progress
    }

    /// The indicator's state for whichever meeting the menu bar is showing, or
    /// `nil` when there is nothing to draw.
    private func currentMeetingProgress() -> MeetingProgressPresentation? {
        guard let event = events.nextEvent() else { return nil }
        return MeetingProgressPolicy.presentation(
            start: event.startDate,
            end: event.endDate,
            now: Date(),
            leadMinutes: Defaults[.eventActionHighlightMinutes]
        )
    }

    private func ensureStatusBarButtonIsVisible(_ button: NSStatusBarButton) {
        guard button.image == nil,
              button.title.isEmpty,
              button.attributedTitle.string.isEmpty
        else { return }

        button.image = MenuStyleConstants.iconNamed(MenuStyleConstants.appIconName)
        button.image?.size = MenuStyleConstants.iconSize
        button.imagePosition = .imageLeft
    }

    /*
     * -----------------------
     * MARK: - Actions
     * ------------------------
     */

    @objc func createMeetingAction() {
        createMeeting()
    }

    @objc
    func joinNextMeeting() {
        if let nextEvent = events.nextEvent() {
            dependencies.send(.joinMeeting(eventID: nextEvent.id))
        } else {
            AppMessageCenter.shared.post(.nextMeetingMissing)
        }
    }

    @objc
    func joinEvent(sender: NSMenuItem) {
        guard let event = sender.representedObject as? MBEvent else {
            AppMessageCenter.shared.post(.nextMeetingMissing)
            return
        }
        dependencies.send(.joinMeeting(eventID: event.id))
    }

    @objc
    func dismissNextMeetingAction() {
        if let nextEvent = events.nextEvent() {
            dependencies.send(.dismissMeeting(eventID: nextEvent.id))
            AppMessageCenter.shared.post(.meetingDismissed(title: nextEvent.title))

            updateTitle()
            reconcileNotifications()
        }
    }

    @objc
    func undismissMeetingsActions() {
        dependencies.send(.clearDismissedMeetings)
        AppMessageCenter.shared.post(.allDismissalsRemoved)

        updateTitle()
        reconcileNotifications()
    }

    @objc
    func openLinkFromClipboardAction() {
        openLinkFromClipboard()
    }

    @objc
    func toggleMeetingTitleVisibility() {
        dependencies.send(.toggleMeetingTitleVisibility)
    }

    @objc
    func joinBookmark(sender: NSMenuItem) {
        if let bookmark: Bookmark = sender.representedObject as? Bookmark {
            MeetingOpener.open(
                meetingLink: MeetingLink(service: MeetingServices(rawValue: bookmark.service), url: bookmark.url))
        }
    }

    @objc
    func clickOnEvent(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            dependencies.send(.joinMeeting(eventID: event.id))
        }
    }

    @objc
    func joinMeetingLinkCandidate(sender: NSMenuItem) {
        if let candidate = sender.representedObject as? MeetingLinkCandidate {
            MeetingOpener.open(
                meetingLink: MeetingLink(service: candidate.service, url: candidate.url))
        }
    }

    @objc
    func openEventInCalendar(sender: NSMenuItem) {
        // The menu attaches the provider-specific calendar URL directly
        // (ical://ekevent/… for EventKit, htmlLink for Google).
        if let url = sender.representedObject as? URL {
            url.openInDefaultBrowser()
        }
    }

    @objc
    func openPrepLink(sender: NSMenuItem) {
        // The menu attaches a meeting-prep reference URL (Figma, Notion, GitHub,
        // Google Docs/…, generic) extracted from the invite. Open it in the
        // default browser, like the other reference-link actions.
        if let url = sender.representedObject as? URL {
            openReferenceURL(url)
        }
    }

    /// Opens a reference URL (prep link, alternate meeting link) in the default
    /// browser. Shared by the NSMenu's `openPrepLink(sender:)` and the SwiftUI
    /// panel's `openURL` handler.
    func openReferenceURL(_ url: URL) {
        url.openInDefaultBrowser()
    }

    // MARK: - Reminders (Dot parity)

    @objc
    func toggleReminderComplete(sender: NSMenuItem) {
        guard let reminder = sender.representedObject as? MBReminder else { return }
        completeReminder(reminder)
    }

    func completeReminder(_ reminder: MBReminder) {
        dependencies.send(.completeReminder(id: reminder.id))
    }

    @objc
    func snoozeReminder(sender: NSMenuItem) {
        guard let command = sender.representedObject as? ReminderSnoozeCommand else { return }
        dependencies.send(.snoozeReminder(id: command.reminderID, option: command.option))
    }

    func snoozeReminder(_ reminder: MBReminder, option: ReminderSnoozeOption) {
        dependencies.send(.snoozeReminder(id: reminder.id, option: option))
    }

    @objc
    func openReminderInApp(sender: NSMenuItem) {
        guard let reminder = sender.representedObject as? MBReminder else { return }
        openReminderInApp(reminder)
    }

    func openReminderInApp(_ reminder: MBReminder) {
        // Try the reminder's deep link first; fall back to just opening Reminders.
        if let deepLink = URL(string: "x-apple-reminderkit://REMCDReminder/\(reminder.id)") {
            NSWorkspace.shared.open(deepLink)
        } else if let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.reminders"
        ) {
            NSWorkspace.shared.open(appURL)
        }
    }

    @objc func handleManualRefresh() {
        dependencies.send(.refreshCalendars)
    }

    @objc func reconnectProviderAction() {
        dependencies.send(.changeProvider(stateProvider, signOut: true))
    }

    @objc func openCalendarPermissionsAction() {
        NSWorkspace.shared.open(Links.calendarPreferences)
    }

    @objc
    func dismissEvent(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            dismiss(event: event)
        }
    }

    func dismiss(event: MBEvent) {
        dependencies.send(.dismissMeeting(eventID: event.id))

        updateTitle()
        reconcileNotifications()
    }

    @objc
    func undismissEvent(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            undismiss(event: event)
        }
    }

    func undismiss(event: MBEvent) {
        dependencies.send(.undismissMeeting(eventID: event.id))

        updateTitle()
        reconcileNotifications()
    }

    /// Quick-copy (Dot parity): any detail row carrying a string in
    /// `representedObject` — location, organizer, attendee — copies it to the
    /// pasteboard when clicked.
    @objc
    func copyDetailAction(sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        copyDetail(value)
    }

    /// Copies a trimmed detail string to the pasteboard, ignoring blanks. Shared
    /// by the NSMenu's quick-copy rows and the panel's `copyText` handler.
    func copyDetail(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
    }

    @objc
    func copyEventMeetingLink(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            copyMeetingLink(for: event)
        }
    }

    func copyMeetingLink(for event: MBEvent) {
        if let meetingLink = event.meetingLink {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(meetingLink.url.absoluteString, forType: .string)
        } else {
            AppMessageCenter.shared.post(.meetingLinkMissing(title: event.title))
        }
    }

    /// Copies the meeting's id (or room name) rather than its whole URL — what
    /// you need for a phone bridge, or to paste into a client already signed in.
    ///
    /// Callers only offer this when `meetingIdentifier` is non-nil, so reaching
    /// here without one means the event changed underneath the open menu; the
    /// clipboard is left alone rather than cleared to nothing.
    func copyMeetingIdentifier(for event: MBEvent) {
        guard let identifier = event.meetingIdentifier else {
            AppMessageCenter.shared.post(.meetingLinkMissing(title: event.title))
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(identifier.value, forType: .string)
    }

    @objc
    func emailAttendees(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            emailAttendees(for: event)
        }
    }

    func emailAttendees(for event: MBEvent) {
        MeetingOpener.emailAttendees(for: event)
    }

    @objc
    func openEventInFantastical(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            openInFantastical(startDate: event.startDate, title: event.title)
        }
    }

    @objc
    func openPreferencesAction() {
        dependencies.openPreferences()
    }

    @objc
    func openCalendarAction() {
        dependencies.openCalendar()
    }

    @objc
    func openWorldClockAction() {
        dependencies.openWorldClock()
    }

    /// Opens the camera/mic pre-call preview standalone (no event → no Join
    /// button). Reached from the right-click "Camera check…" quick action and the
    /// keyboard shortcut.
    @objc
    func openCameraPreviewAction() {
        dependencies.openCameraPreview(nil)
    }

    /// Opens the camera/mic preview for a specific event so the preview shows a
    /// contextual "Join meeting" button. Reached from the per-event submenu.
    @objc
    func previewCameraForEventAction(sender: NSMenuItem) {
        guard let event = sender.representedObject as? MBEvent else { return }
        dependencies.openCameraPreview(event)
    }

    // MARK: - Event editing (Dot parity)

    @objc
    func newEventAction() {
        dependencies.newEvent()
    }

    @objc
    func editEventAction(sender: NSMenuItem) {
        guard let event = sender.representedObject as? MBEvent else { return }
        editEvent(event)
    }

    func editEvent(_ event: MBEvent) {
        dependencies.editEvent(event)
    }

    /// Destructive: confirm via NSAlert BEFORE deleting. The actual delete +
    /// refresh runs through the injected dependency (EventKit writer).
    @objc
    func deleteEventAction(sender: NSMenuItem) {
        guard let event = sender.representedObject as? MBEvent else { return }
        confirmAndDeleteEvent(event)
    }

    /// The destructive delete flow shared by the NSMenu item and the SwiftUI
    /// panel: an NSAlert confirmation (with the recurring this-event /
    /// this-and-future choice) before the injected EventKit write.
    func confirmAndDeleteEvent(_ event: MBEvent) {
        let alert = NSAlert()
        alert.messageText = "event_editor_delete_confirm_title".loco()
        alert.informativeText = "event_editor_delete_confirm_message".loco(event.title)
        alert.alertStyle = .warning

        if event.recurrent {
            // Recurring: offer the delete scope directly as destructive buttons.
            let thisButton = alert.addButton(withTitle: "event_editor_delete_this_event".loco())
            thisButton.hasDestructiveAction = true
            let futureButton = alert.addButton(withTitle: "event_editor_delete_this_and_future".loco())
            futureButton.hasDestructiveAction = true
            alert.addButton(withTitle: "event_editor_cancel".loco())

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                dependencies.deleteEvent(event, .thisEvent)
            case .alertSecondButtonReturn:
                dependencies.deleteEvent(event, .thisAndFuture)
            default:
                return
            }
        } else {
            let deleteButton = alert.addButton(withTitle: "event_editor_delete".loco())
            deleteButton.hasDestructiveAction = true
            alert.addButton(withTitle: "event_editor_cancel".loco())

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            dependencies.deleteEvent(event, .thisEvent)
        }
    }

    private var stateProvider: EventStoreProvider {
        dependencies.appState().activeProvider
    }

    @objc
    func openChangelogAction() {
        dependencies.openChangelog()
    }

    @objc
    func quitAction() {
        dependencies.quit()
    }
}

@MainActor
enum StatusBarTitleRenderer {
    static func attributedTitle(for presentation: StatusBarPresentation) -> NSAttributedString {
        switch presentation.layout {
        case .none:
            return NSAttributedString(string: "")
        case .inline(let showTime):
            var eventTitle = presentation.title
            if showTime {
                eventTitle += " " + presentation.time
            }
            return NSAttributedString(
                string: eventTitle,
                attributes: titleAttributes(
                    style: presentation.titleStyle,
                    font: titleFont(
                        ofSize: MenuStyleConstants.defaultFontSize,
                        emphasized: presentation.emphasizeTitle
                    )
                )
            )
        case .stacked:
            return stackedTitle(for: presentation)
        }
    }

    /// Weight, not colour, carries the emphasis: the menu bar sits on wallpaper
    /// the app cannot see, so a colour that reads as urgent against one is
    /// invisible against another, and the system already owns menu-bar tinting
    /// for light/dark and accent. Weight is legible everywhere.
    private static func titleFont(ofSize size: CGFloat, emphasized: Bool) -> NSFont {
        emphasized
            ? NSFont.systemFont(ofSize: size, weight: .bold)
            : NSFont.systemFont(ofSize: size)
    }

    private static func stackedTitle(for presentation: StatusBarPresentation) -> NSAttributedString {
        let title = NSMutableAttributedString(
            string: presentation.title,
            attributes: titleAttributes(
                style: presentation.titleStyle,
                font: titleFont(ofSize: 12, emphasized: presentation.emphasizeTitle),
                baselineOffset: -3
            )
        )
        title.append(
            NSAttributedString(
                string: "\n" + presentation.time,
                attributes: [
                    NSAttributedString.Key.font: NSFont.systemFont(ofSize: 9),
                    NSAttributedString.Key.foregroundColor: NSColor.lightGray
                ]
            ))

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 0.7
        paragraphStyle.alignment = .center
        title.addAttributes(
            [NSAttributedString.Key.paragraphStyle: paragraphStyle],
            range: NSRange(location: 0, length: title.length)
        )
        return title
    }

    private static func titleAttributes(
        style: StatusBarTitleStyle,
        font: NSFont,
        baselineOffset: CGFloat? = nil
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        if let baselineOffset {
            attributes[.baselineOffset] = baselineOffset
        }
        switch style {
        case .normal:
            break
        case .inactive:
            attributes[.foregroundColor] = NSColor.disabledControlTextColor
        case .underlined:
            attributes[.underlineStyle] =
                NSUnderlineStyle.single.rawValue
                | NSUnderlineStyle.patternDot.rawValue
                | NSUnderlineStyle.byWord.rawValue
        }
        return attributes
    }
}

private func statusBarCalendar() -> Calendar {
    var calendar = Calendar.current
    calendar.locale = I18N.instance.locale
    return calendar
}

/// Carries a reminder + chosen snooze option through a menu item's
/// `representedObject` to the `snoozeReminder(sender:)` action.
struct ReminderSnoozeCommand {
    let reminderID: String
    let option: ReminderSnoozeOption
}
