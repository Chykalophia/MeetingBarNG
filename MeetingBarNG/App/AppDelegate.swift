//
//  AppDelegate.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 24.04.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
//  Modified for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026:
//  remove the StoreKit patronage service and its lifecycle wiring; add the month
//  calendar window entry point (builds the fetch/join handlers and wires
//  openCalendar into the status-bar dependencies); add the in-app event editor
//  entry points (build create/update/delete handlers over the EventKit writer,
//  refresh the sync after each write, and wire newEvent/editEvent/deleteEvent
//  into the status-bar dependencies); add the camera/mic pre-call preview entry
//  point (builds the join handlers over the AppModel and wires openCameraPreview
//  into the status-bar dependencies); add the multi-zone world-clock panel window
//  entry point (wires openWorldClock into the status-bar dependencies); wire the
//  SwiftUI dropdown panel (openDropdownPanel — the default dropdown) into the
//  status-bar dependencies; request
//  EventKit calendar access on a normal post-onboarding launch when it is still
//  undetermined, so the app prompts and registers with TCC instead of silently
//  holding no access.
//

import AppKit
import Combine
import Defaults
import KeyboardShortcuts
import UserNotifications

@MainActor
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: StatusBarItemController!
    var calendarSync: CalendarSync!
    /// Reminders live in their own EventKit store so their permission is
    /// requested independently (and only on opt-in). Shared instance so the
    /// preferences toggle, sync, and write paths all target the same store.
    let remindersStore = RemindersStore.shared
    private var remindersSync: RemindersSync!
    let notificationScheduler = NotificationScheduler()
    let snoozeService = SnoozeService()
    private var notificationCenterDelegate: NotificationCenterDelegate?
    private var notificationActionHandler: NotificationActionHandler?
    private(set) var appModel: AppModel?
    private let lifecycleObserver = LifecycleObserver()
    private let urlHandler = URLHandler()
    private let windowCoordinator = WindowCoordinator()

    private var launchTask: Task<Void, Never>?
    private var notificationSetupTask: Task<Void, Never>?
    private var statusLoopTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_: Notification) {
        // When launched as a test host, skip the entire launch flow so tests
        // don't trigger onboarding, status bar setup, or calendar sync.
        guard !AppMessageCenter.shouldSuppressSystemUI() else { return }

        // Migrate legacy per-provider browser keys → providerBrowsers map
        MeetingOpenPreferencesMigration.migrateDefaultsIfNeeded()
        StatusBarTitleFormatMigration.migrateDefaultsIfNeeded()
        TimeFormatDefaultMigration.migrateDefaultsIfNeeded()
        ChangelogResetMigration.migrateDefaultsIfNeeded()
        MenuBarTimeFormatDefaultsMigration.migrateDefaultsIfNeeded()
        DropdownModuleMergeMigration.migrateDefaultsIfNeeded()

        // Handle windows closing closing
        NotificationCenter.default.addObserver(
            self, selector: #selector(AppDelegate.windowClosed),
            name: NSWindow.willCloseNotification, object: nil
        )
        //

        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            Defaults[.appVersion] = appVersion
        }

        statusBarItem = StatusBarItemController()

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(AppDelegate.handleURLEvent(getURLEvent:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        launchTask = Task { [weak self] in
            guard let self else { return }
            let manager = await CalendarSync()
            guard !Task.isCancelled else {
                manager.stop()
                return
            }
            calendarSync = manager
            if Defaults[.onboardingCompleted] {
                setup()
            } else {
                setup(triggerInitialRefresh: false)
                presentOnboardingWindow()
            }
            launchTask = nil
        }
    }

    /// Opens the first-run setup window from the cold-launch path when setup is
    /// incomplete.
    func presentOnboardingWindow() {
        guard let appModel else { return }
        windowCoordinator.openOnboardingWindow(
            appModel: appModel,
            onProviderSelected: { [weak appModel] provider in
                guard let appModel else {
                    return .failed("Application state is unavailable")
                }
                return await appModel.changeProvider(to: provider)
            },
            onComplete: { [weak appModel] provider in
                guard let appModel else {
                    return .failed("Application state is unavailable")
                }
                let result = await appModel.completeOnboarding(with: provider)
                if result == .success {
                    appModel.handleLaunch()
                }
                return result
            }
        )
    }

    func setup(triggerInitialRefresh: Bool = true) {
        guard appModel == nil else { return }
        let sync = RemindersSync(store: remindersStore)
        remindersSync = sync
        let env = AppEnvironment.live(
            calendarSync: calendarSync,
            remindersSync: sync,
            remindersStore: remindersStore,
            notificationScheduler: notificationScheduler,
            snoozeService: snoozeService,
            openPreferences: { [weak self] in
                self?.openPreferencesWindow(nil)
            },
            openDropdown: { [weak self] in
                guard let self else { return }
                // Same entry point the status-item click uses, so a deep link and
                // a click cannot diverge — but idempotent: `openDropdownPanel`
                // toggles, and asking to open something already open should not
                // close it.
                guard !self.windowCoordinator.isDropdownPanelOpen else { return }
                self.statusBarItem?.toggleDropdownPanel()
            },
            resumeOAuthFlow: { [weak self] url in
                guard let calendarSync = self?.calendarSync else { return }
                calendarSync.repository.resumeAuthorizationFlow(with: url)
            }
        )
        let model = AppModel(environment: env)
        appModel = model
        AppRuntimeBridge.shared.install(appModel: model)

        let actionHandler = NotificationActionHandler(
            isScreenLocked: { [weak model] in model?.state.screenIsLocked ?? false },
            send: { [weak model] action in model?.send(action) },
            showFullscreen: { [weak self] event in
                self?.windowCoordinator.openFullscreenNotificationWindow(event: event)
            },
            runEventStartScript: { event in
                runMeetingStartsScript(event: event, type: .meetingStart)
            }
        )
        notificationActionHandler = actionHandler
        notificationScheduler.setActionSink(actionHandler)

        var statusBarDependencies = StatusBarDependencies(
            appState: { [weak model] in model?.state ?? AppState() },
            events: { [weak model] in model?.state.events ?? [] },
            send: { [weak model] action in model?.send(action) },
            openPreferences: { [weak self] in self?.openPreferencesWindow(nil) },
            openChangelog: { [weak self] in self?.openChangelogWindow(nil) },
            openCommandBar: { [weak self] in self?.openCommandBarWindow() },
            openDropdownPanel: { [weak self] state, handlers, anchor in
                self?.windowCoordinator.openDropdownPanel(
                    state: state,
                    handlers: handlers,
                    relativeTo: anchor
                )
            },
            openCalendar: { [weak self] in self?.openCalendarWindow() },
            openWorldClock: { [weak self] in self?.openWorldClockWindow() },
            openCameraPreview: { [weak self] event in self?.openCameraPreviewWindow(event: event) },
            newEvent: { [weak self] in self?.openNewEventWindow() },
            fetchEvents: dateRangeEventFetch(),
            editEvent: { [weak self] event in self?.openEditEventWindow(event) },
            deleteEvent: { [weak self] event, span in self?.deleteEvent(event, span: span) },
            quit: { [weak self] in self?.quit(nil) }
        )
        #if DEBUG
        statusBarDependencies.openDebugHarness = { [weak self] in self?.toggleDebugHarnessWindow() }
        #endif
        statusBarItem.configure(dependencies: statusBarDependencies)

        // Drive status bar from AppModel state: update title and menu whenever
        // events change.
        model.$state
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.statusBarItem.updateTitle()
            }
            .store(in: &cancellables)

        let ncDelegate = NotificationCenterDelegate { [weak model] response in
            model?.send(.notificationResponse(response))
        }
        notificationCenterDelegate = ncDelegate
        UNUserNotificationCenter.current().delegate = ncDelegate
        notificationSetupTask = Task { @MainActor [weak self] in
            await ensureNotificationAuthorization()
            guard !Task.isCancelled else { return }
            registerNotificationCategories()
            self?.notificationSetupTask = nil
        }

        startAsyncLoops()
        if Defaults[.browsers].isEmpty {
            addInstalledBrowser()
        }

        lifecycleObserver.onScreenLocked = { [weak self] in
            self?.appModel?.handleScreenLock()
        }
        lifecycleObserver.onScreenUnlocked = { [weak self] in
            self?.appModel?.handleScreenUnlock()
        }
        lifecycleObserver.onDidWake = { [weak self] in
            self?.appModel?.handleWake()
        }
        lifecycleObserver.onSystemClockChanged = { [weak self] in
            self?.handleSystemClockChange()
        }
        lifecycleObserver.onTimezoneChanged = { [weak self] in
            self?.handleTimezoneChange()
        }
        lifecycleObserver.onDayChanged = { [weak self] in
            self?.appModel?.handleDayChange()
        }
        lifecycleObserver.start()

        if triggerInitialRefresh {
            model.handleLaunch()
            requestCalendarAccessIfNeeded(model: model)
            // Only fetch reminders at launch when the feature is enabled AND
            // access is already granted — the permission prompt is exclusively
            // triggered from the preferences toggle, never here.
            if Defaults[.showRemindersInMenu], remindersStore.isAccessGranted {
                sync.refreshSubject.send()
            }
        }
    }

    /// On a normal (post-onboarding) launch the provider switch that would
    /// otherwise trigger the EventKit permission prompt never runs, so a fresh
    /// install / TCC reset / newly code-signed binary can silently hold no
    /// calendar access — and, because the app never registers with TCC, there
    /// is nothing to toggle in System Settings ▸ Privacy ▸ Calendars.
    ///
    /// When macOS Calendar is the active provider and its authorization is still
    /// `.notDetermined`, request access now by routing through the existing
    /// `.changeProvider` action (switchProvider → signIn →
    /// requestFullAccessToEvents), so macOS prompts, the app registers with TCC,
    /// and the resulting calendar/event fetch + state wiring all run.
    ///
    /// No-op when access is already granted (`.authorized`, a redundant prompt)
    /// or `.denied`/`.restricted` (a request would not prompt — the user must
    /// grant it in System Settings). Fires once per launch: `setup()` guards on
    /// `appModel == nil`, and this only runs on the initial-refresh path.
    private func requestCalendarAccessIfNeeded(model: AppModel) {
        guard model.state.activeProvider == .macOSEventKit,
              PermissionReporter.calendarAuthorizationStatus() == .notDetermined else {
            return
        }
        MeetingBarLogger.calendar.info(
            "Requesting EventKit calendar access on launch (authorization not determined)"
        )
        model.send(.changeProvider(model.state.activeProvider, signOut: false))
    }

    /*
     * -----------------------
     * MARK: - Scheduled tasks
     * ------------------------
     */
    private func startAsyncLoops() {
        statusLoopTask?.cancel()

        // Redraw status bar item on hh:mm:00
        statusLoopTask = Task(priority: .utility) { [weak self] in
            while let self, !Task.isCancelled {
                // Compute now & next minute boundary
                let now = Date()
                let calendar = Calendar.current
                let nextMinute = calendar.nextDate(
                    after: now,
                    matching: DateComponents(second: 0),
                    matchingPolicy: .nextTime
                )!

                // Sleep until that boundary
                let interval = nextMinute.timeIntervalSince(now)
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(max(interval, 0) * Double(NSEC_PER_SEC))
                    )
                } catch {
                    return
                }

                // Once we hit hh:mm:00, redraw
                await MainActor.run {
                    self.statusBarItem.updateTitle()
                }
            }
        }
    }

    private func handleSystemClockChange() {
        appModel?.handleSystemClockChange()
        startAsyncLoops()
    }

    private func handleTimezoneChange() {
        appModel?.handleTimezoneChange()
        startAsyncLoops()
    }

    /*
     * -----------------------
     * MARK: - Windows
     * ------------------------
     */

    @objc
    func openChangelogWindow(_: NSStatusBarButton?) {
        windowCoordinator.openChangelogWindow()
    }

    @objc
    func openPreferencesWindow(_: NSStatusBarButton?) {
        windowCoordinator.openPreferencesWindow(
            appModel: appModel,
            calendarSync: calendarSync
        )
    }

    func openCommandBarWindow() {
        let model = appModel
        windowCoordinator.openCommandBarWindow(
            handlers: CommandBarHandlers(
                events: { [weak model] in model?.state.events ?? [] },
                send: { [weak model] action in model?.send(action) },
                openPreferences: { [weak self] in self?.openPreferencesWindow(nil) },
                createMeeting: { createMeeting() }
            )
        )
    }

    /// Events in `[from, to)` across the user's selected calendars, independent
    /// of the main today/tomorrow sync.
    ///
    /// Shared by the calendar WINDOW and the dropdown's compact month grid. It
    /// was inline in `openCalendarWindow`; the panel needing the same data is
    /// exactly the moment to name it rather than write it twice.
    private func dateRangeEventFetch() -> @MainActor (Date, Date) async throws -> [MBEvent] {
        let sync = calendarSync
        return { [weak sync] from, to in
            guard let repository = sync?.repository else { return [] }
            let allCalendars = try await repository.fetchAllCalendars()
            let selectedIDs = AppSettings.selectedCalendarIDs(
                for: repository.activeProviderName
            )
            let selected = allCalendars.filter { selectedIDs.contains($0.id) }
            return try await repository.fetchEventsForDateRange(
                for: selected, from: from, to: to
            )
        }
    }

    /// Opens the month calendar window. Joining forwards to the AppModel's join
    /// action.
    func openCalendarWindow() {
        let model = appModel
        windowCoordinator.openCalendarWindow(
            handlers: CalendarWindowHandlers(
                fetchEvents: dateRangeEventFetch(),
                join: { [weak model] eventID in
                    model?.send(.joinMeeting(eventID: eventID))
                }
            )
        )
    }

    /// Opens the multi-zone world-clock panel window. It reads its zones and
    /// time-format from `Defaults` and refreshes each minute on its own, so no
    /// handlers are threaded through.
    func openWorldClockWindow() {
        windowCoordinator.openWorldClockWindow()
    }

    /// Opens the camera/mic pre-call preview ("mirror check"). When `event` is
    /// non-nil the preview shows a contextual "Join meeting" button that forwards
    /// to the AppModel's join action; opened standalone (event == nil) there is no
    /// Join button. Camera/mic access is requested lazily inside the preview
    /// controller on first open, never here.
    func openCameraPreviewWindow(event: MBEvent?) {
        let model = appModel
        windowCoordinator.openCameraPreviewWindow(
            handlers: CameraPreviewHandlers(
                joinEventID: event?.id,
                join: { [weak model] eventID in
                    model?.send(.joinMeeting(eventID: eventID))
                }
            )
        )
    }

    /// Opens the in-app event editor to create a new event (EventKit write path).
    func openNewEventWindow() {
        windowCoordinator.openEventEditorWindow(
            mode: .create,
            handlers: makeEventEditorHandlers()
        )
    }

    /// Opens the in-app event editor prefilled to edit `event`.
    func openEditEventWindow(_ event: MBEvent) {
        windowCoordinator.openEventEditorWindow(
            mode: .edit(event),
            handlers: makeEventEditorHandlers()
        )
    }

    /// Deletes `event` via the EventKit writer and refreshes the menu. Called
    /// from the per-event "Delete…" menu item after its NSAlert confirmation.
    /// `span` scopes a recurring delete (this occurrence vs this-and-future).
    func deleteEvent(_ event: MBEvent, span: EventEditSpan) {
        let sync = calendarSync
        Task {
            do {
                try await EventKitEventWriter.shared.delete(id: event.scriptIdentifier, span: span)
                sync?.refreshSubject.send()
            } catch {
                MeetingBarLogger.calendar.error(
                    "Event delete failed: \(String(describing: error), privacy: .private)"
                )
            }
        }
    }

    /// Builds the editor handlers: each write forwards to the EventKit writer and,
    /// on success, triggers a `CalendarSync` refresh so the menu updates. The
    /// `dismiss` here is a placeholder — `WindowCoordinator` injects the real
    /// window-close closure since it owns the window.
    private func makeEventEditorHandlers() -> EventEditorHandlers {
        let sync = calendarSync
        return EventEditorHandlers(
            create: { draft in
                _ = try await EventKitEventWriter.shared.create(draft: draft)
                sync?.refreshSubject.send()
            },
            update: { id, draft, span in
                try await EventKitEventWriter.shared.update(id: id, draft: draft, span: span)
                sync?.refreshSubject.send()
            },
            delete: { id, span in
                try await EventKitEventWriter.shared.delete(id: id, span: span)
                sync?.refreshSubject.send()
            },
            writableCalendars: { EventKitEventWriter.shared.writableCalendars() },
            dismiss: {}
        )
    }

    @objc
    func windowClosed(notification: NSNotification) {
        let window = notification.object as? NSWindow
        windowCoordinator.handleWindowClosed(
            window,
            onboardingCompleted: Defaults[.onboardingCompleted],
            onIncompleteOnboardingClosed: { [weak self] in
                guard let self else { return }
                NSApplication.shared.terminate(self)
            },
            onChangelogClosed: {
                // No redraw needed: the panel reads the acknowledgement when it
                // next opens, which is what decides whether "What's new?" shows.
                AppSettings.acknowledgeCurrentChangelog()
            }
        )
    }

    /*
     * -----------------------
     * MARK: - Actions
     * ------------------------
     */

    @objc
    func handleURLEvent(
        getURLEvent event: NSAppleEventDescriptor, replyEvent _: NSAppleEventDescriptor
    ) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }

        #if DEBUG
        // Intercepted ahead of the router: a development-only URL should not
        // acquire an `AppRoute` case and an `AppEnvironment` closure that the
        // release build still compiles. See `DropdownInspectorWindow`.
        if DropdownInspectorWindow.matches(url) {
            toggleDropdownInspectorWindow()
            return
        }
        if DebugHarnessWindow.matches(url) {
            toggleDebugHarnessWindow()
            return
        }
        #endif

        appModel?.send(.openRoute(urlHandler.route(for: url)))
    }

    #if DEBUG
    /// Shows (or hides) the dropdown panel in a window that stays open, so it can
    /// be screenshotted and inspected. Reached only via
    /// `meetingbar://dropdown-debug`.
    private func toggleDropdownInspectorWindow() {
        guard let snapshot = statusBarItem?.dropdownPanelSnapshotForInspector() else { return }
        windowCoordinator.toggleDropdownInspectorWindow(
            state: snapshot.state,
            handlers: snapshot.handlers,
            anchor: snapshot.anchor
        )
    }

    /// Opens the development harness. Reached from the status item's right-click
    /// menu, or via `meetingbar://debug-harness`.
    func toggleDebugHarnessWindow() {
        windowCoordinator.openDebugHarnessWindow(
            handlers: DebugHarnessHandlers(
                apply: { [weak self] scenario in
                    // A scenario with no builder is "go back to the real
                    // calendar", which is `nil` rather than an empty list —
                    // an empty list is itself a scenario.
                    self?.statusBarItem?.debugOverrideEvents(scenario.build.map { $0(Date()) })
                },
                summary: { [weak self] in
                    self?.statusBarItem?.debugRenderSummary()
                        ?? DebugHarnessHandlers().summary()
                }
            )
        )
    }
    #endif

    @objc
    func quit(_: Any?) {
        statusLoopTask?.cancel()
        NSApplication.shared.terminate(self)
    }

    /// Relaunching an already-running instance (Finder, Dock, `open`, CLI) sends
    /// a reopen event. MeetingBarNG is a menu-bar (accessory) app with no main
    /// window, so that would otherwise do nothing visible — leaving the app
    /// unreachable when its status-bar icon is hidden (e.g. overflowed under the
    /// notch). Surface Preferences instead so there's always a way back in.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        // While onboarding is still open, leave that window in charge.
        guard Defaults[.onboardingCompleted] else { return true }
        openPreferencesWindow(nil)
        return true
    }

    func applicationWillTerminate(_: Notification) {
        launchTask?.cancel()
        launchTask = nil
        notificationSetupTask?.cancel()
        notificationSetupTask = nil
        statusLoopTask?.cancel()
        statusLoopTask = nil
        lifecycleObserver.stop()
        appModel?.handleWillTerminate()
        notificationScheduler.stop()
        calendarSync?.stop()
        remindersSync?.stop()
        cancellables.removeAll()
        statusBarItem?.removeFromStatusBar()
    }
}
