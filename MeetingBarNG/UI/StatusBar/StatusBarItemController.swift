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
//  reorderable modules); remove the "Rate App" action that opened the original
//  App Store listing; add an "Open calendar" entry point (dependency closure,
//  keyboard shortcut, and @objc handler) for the month calendar window; add the
//  in-app event editor entry points (new/edit/delete dependency closures, the
//  .newEventShortcut registration, and @objc handlers, with a destructive NSAlert
//  before delete).
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
    var openCalendar: @MainActor () -> Void = {}
    var newEvent: @MainActor () -> Void = {}
    var editEvent: @MainActor (MBEvent) -> Void = { _ in }
    var deleteEvent: @MainActor (MBEvent) -> Void = { _ in }
    var quit: @MainActor () -> Void = {}
}

/// creates the menu in the system status bar, creates the menu items and controls the whole lifecycle.
@MainActor
final class StatusBarItemController {
    var statusItem: NSStatusItem!
    var statusItemMenu: NSMenu!

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

    init() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        statusItemMenu = NSMenu(title: "MeetingBar in Status Bar Menu")

        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusMenuBarAction)
        statusItem.button?.sendAction(on: [
            NSEvent.EventTypeMask.rightMouseDown, NSEvent.EventTypeMask.leftMouseUp,
            NSEvent.EventTypeMask.leftMouseDown
        ])

        // Temporary icon and menu before app delegate setup
        statusItem.button?.image = MenuStyleConstants.iconNamed(MenuStyleConstants.appIconName)
        statusItem.button?.image?.size = MenuStyleConstants.iconSize
        statusItem.button?.imagePosition = .imageLeft
        let menuItem = statusItemMenu.addItem(
            withTitle: "window_title_onboarding".loco(), action: nil, keyEquivalent: "")
        menuItem.isEnabled = false

        setupDefaultsObservers()
        setupKeyboardShortcuts()
    }

    private func setupDefaultsObservers() {
        // For all these keys, just redraw:
        Defaults.publisher(
            keys: .statusbarEventTitleLength, .eventTimeFormat,
            .eventTitleIconFormat, .showEventMaxTimeUntilEventThreshold,
            .showEventMaxTimeUntilEventEnabled, .showEventDetails,
            .shortenEventTitle, .menuEventTitleLength,
            .showEventEndTime, .showMeetingServiceIcon,
            .showEventCalendarColor,
            .timeFormat, .bookmarks,
            .personalEventsAppereance, .pastEventsAppereance,
            .declinedEventsAppereance, .ongoingEventVisibility,
            .showTimelineInMenu, .hideFinishedEventsInMenu,
            .menuBarTokens, .menuBarCountdownStyle, .menuBarDateStyle,
            .menuBarProgressStyle, .menuBarWorldClockTimeZone, .menuBarWorldClockLabel,
            .showGreetingInMenu, .greetingName,
            .showRemindersInMenu, .remindersIncludeOverdue,
            .dropdownModuleOrder, .showMeetingControlInMenu,
            .showAgendaInMenu, .showJoinSectionInMenu, .showBookmarksInMenu,
            options: []
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.updateTitle()
            self?.updateMenu()
        }
        .store(in: &cancellables)

        Defaults.publisher(.eventTitleFormat, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenu()
                self?.updateTitle()
                self?.reconcileNotifications()
            }
            .store(in: &cancellables)

        Defaults.publisher(.preferredLanguage, options: [.initial])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                if I18N.instance.changeLanguage(to: change.newValue) {
                    self?.updateMenu()
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
            Task { @MainActor in self.openMenu() }
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

        KeyboardShortcuts.onKeyUp(for: .newEventShortcut) {
            Task { @MainActor in self.dependencies.newEvent() }
        }
    }

    @objc
    func statusMenuBarAction(sender _: NSStatusItem) {
        let event = NSApp.currentEvent

        if event?.type == .rightMouseUp {
            // Right button click → compact quick-actions menu.
            showQuickActionsMenu()
        } else if event == nil || event?.type == .leftMouseDown || event?.type == .leftMouseUp {
            // show the menu as normal
            openMenu()
        }
    }

    func openMenu() {
        statusItem.menu = statusItemMenu
        statusItem.button?.performClick(nil)  // ...and click
        statusItem.menu = nil
    }

    /// Pops up the right-click quick-actions menu at the status item.
    func showQuickActionsMenu() {
        var appState = dependencies.appState()
        appState.events = events
        let menuState = StatusBarMenuState.make(from: appState)
        let builder = MenuBuilder(target: self, state: menuState, installationDate: installationDate)
        let menu = builder.buildQuickActionsMenu()
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
        let nextEvent = events.nextEvent().map(StatusBarEventPresentationInput.init)

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

    func renderStatusBar(_ presentation: StatusBarPresentation) {
        guard let button = statusItem.button else { return }

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
     * MARK: - MENU SECTIONS
     * ------------------------
     */

    func updateMenu() {
        // Don't update the menu while it's open to avoid flickering
        if statusItem.menu != nil {
            return
        }

        var appState = dependencies.appState()
        appState.events = events
        let menuState = StatusBarMenuState.make(from: appState)
        let builder = MenuBuilder(
            target: self, state: menuState, installationDate: installationDate)

        statusItemMenu.autoenablesItems = false

        // Composable dropdown: each module produces a separator-free block; the
        // enabled modules (in the user's stored order) are joined below with a
        // single separator between non-empty blocks. With the default order +
        // all toggles on, this reproduces the classic dropdown layout exactly.
        let modules = DropdownCompositionPolicy.resolve(
            order: Defaults[.dropdownModuleOrder],
            enabled: enabledDropdownModuleRawValues(menuState)
        )

        var blocks: [[NSMenuItem]] = []
        for module in modules {
            switch module {
            case .greeting:
                if menuState.shouldShowGreetingHeader {
                    blocks.append(builder.buildGreetingHeaderBlock())
                }
            case .timeline:
                blocks.append(builder.buildTimelineBlock())
            case .meeting:
                blocks.append(builder.buildMeetingControlSection())
            case .agenda:
                if menuState.hasSelectedCalendars {
                    blocks.append(builder.buildAgendaBlock())
                }
            case .join:
                blocks.append(builder.buildJoinSection(
                    nextEvent: menuState.nextEvent,
                    includeJoinAction: false
                ))
            case .bookmarks:
                if !menuState.meetings.bookmarks.isEmpty {
                    blocks.append(builder.buildBookmarksSection(
                        bookmarks: menuState.meetings.bookmarks))
                }
            }
        }
        // The Preferences footer is pinned, never a module, so the user can't
        // hide Settings/Quit.
        blocks.append(builder.buildPreferencesSection())

        statusItemMenu.removeAllItems()
        for block in blocks where !block.isEmpty {
            if !statusItemMenu.items.isEmpty {
                statusItemMenu.addItem(.separator())
            }
            statusItemMenu.items += block
        }
    }

    /// The raw values of the dropdown modules whose enabled toggle is on, used as
    /// the `enabled` set for `DropdownCompositionPolicy.resolve`. greeting/timeline
    /// reuse the existing preferences; the rest use the MeetingBarNG toggles.
    private func enabledDropdownModuleRawValues(_ menuState: StatusBarMenuState) -> Set<String> {
        var enabled = Set<String>()
        if menuState.showGreetingHeader { enabled.insert(DropdownModule.greeting.rawValue) }
        if menuState.menu.showTimelineInMenu { enabled.insert(DropdownModule.timeline.rawValue) }
        if menuState.menu.showMeetingControlInMenu { enabled.insert(DropdownModule.meeting.rawValue) }
        if menuState.menu.showAgendaInMenu { enabled.insert(DropdownModule.agenda.rawValue) }
        if menuState.menu.showJoinSectionInMenu { enabled.insert(DropdownModule.join.rawValue) }
        if menuState.menu.showBookmarksInMenu { enabled.insert(DropdownModule.bookmarks.rawValue) }
        return enabled
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
            updateMenu()
            reconcileNotifications()
        }
    }

    @objc
    func undismissMeetingsActions() {
        dependencies.send(.clearDismissedMeetings)
        AppMessageCenter.shared.post(.allDismissalsRemoved)

        updateTitle()
        updateMenu()
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

    // MARK: - Reminders (Dot parity)

    @objc
    func toggleReminderComplete(sender: NSMenuItem) {
        guard let reminder = sender.representedObject as? MBReminder else { return }
        dependencies.send(.completeReminder(id: reminder.id))
    }

    @objc
    func snoozeReminder(sender: NSMenuItem) {
        guard let command = sender.representedObject as? ReminderSnoozeCommand else { return }
        dependencies.send(.snoozeReminder(id: command.reminderID, option: command.option))
    }

    @objc
    func openReminderInApp(sender: NSMenuItem) {
        guard let reminder = sender.representedObject as? MBReminder else { return }
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
        updateMenu()
        reconcileNotifications()
    }

    @objc
    func undismissEvent(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            dependencies.send(.undismissMeeting(eventID: event.id))

            updateTitle()
            updateMenu()
            reconcileNotifications()
        }
    }

    @objc
    func copyEventMeetingLink(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            if let meetingLink = event.meetingLink {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(meetingLink.url.absoluteString, forType: .string)
            } else {
                AppMessageCenter.shared.post(.meetingLinkMissing(title: event.title))
            }
        }
    }

    @objc
    func emailAttendees(sender: NSMenuItem) {
        if let event: MBEvent = sender.representedObject as? MBEvent {
            MeetingOpener.emailAttendees(for: event)
        }
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

    // MARK: - Event editing (Dot parity)

    @objc
    func newEventAction() {
        dependencies.newEvent()
    }

    @objc
    func editEventAction(sender: NSMenuItem) {
        guard let event = sender.representedObject as? MBEvent else { return }
        dependencies.editEvent(event)
    }

    /// Destructive: confirm via NSAlert BEFORE deleting. The actual delete +
    /// refresh runs through the injected dependency (EventKit writer).
    @objc
    func deleteEventAction(sender: NSMenuItem) {
        guard let event = sender.representedObject as? MBEvent else { return }

        let alert = NSAlert()
        alert.messageText = "event_editor_delete_confirm_title".loco()
        alert.informativeText = "event_editor_delete_confirm_message".loco(event.title)
        alert.alertStyle = .warning
        let deleteButton = alert.addButton(withTitle: "event_editor_delete".loco())
        deleteButton.hasDestructiveAction = true
        alert.addButton(withTitle: "event_editor_cancel".loco())

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        dependencies.deleteEvent(event)
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
                    font: NSFont.systemFont(ofSize: MenuStyleConstants.defaultFontSize)
                )
            )
        case .stacked:
            return stackedTitle(for: presentation)
        }
    }

    private static func stackedTitle(for presentation: StatusBarPresentation) -> NSAttributedString {
        let title = NSMutableAttributedString(
            string: presentation.title,
            attributes: titleAttributes(
                style: presentation.titleStyle,
                font: NSFont.systemFont(ofSize: 12),
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

enum NextEventState {
    case none
    case afterThreshold(MBEvent)
    case nextEvent(MBEvent)
}

/// Carries a reminder + chosen snooze option through a menu item's
/// `representedObject` to the `snoozeReminder(sender:)` action.
struct ReminderSnoozeCommand {
    let reminderID: String
    let option: ReminderSnoozeOption
}
