//
//  WindowCoordinator.swift
//  MeetingBar
//

import AppKit
import SwiftUI

enum FullscreenNotificationScreenSelectionPolicy {
    static func select<Screen>(
        keyWindowScreen: Screen?,
        mainWindowScreen: Screen?,
        mouseScreen: Screen?,
        mainScreen: Screen?,
        screens: [Screen]
    ) -> Screen? {
        keyWindowScreen ?? mainWindowScreen ?? mouseScreen ?? mainScreen ?? screens.first
    }
}

enum FullscreenNotificationKeyboardPolicy {
    static let escapeKeyCode: UInt16 = 53

    static func shouldDismiss(keyCode: UInt16) -> Bool {
        keyCode == escapeKeyCode
    }
}

final class FullscreenNotificationWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if FullscreenNotificationKeyboardPolicy.shouldDismiss(keyCode: event.keyCode) {
            close()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

final class OnboardingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            close()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

/// Borderless "What's New" window: the ChangelogView paints its own rounded
/// chrome (matching Onboarding), and Escape / the primary button close it —
/// which is what acknowledges the changelog via the close handler.
final class ChangelogWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            close()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

enum ChangelogWindowPresentationPolicy {
    static let contentRect = NSRect(x: 0, y: 0, width: 640, height: 560)
    static let minimumSize = NSSize(width: 560, height: 460)
    static let styleMask: NSWindow.StyleMask = [.resizable]
    static let level: NSWindow.Level = .normal
}

/// Borderless Spotlight-style Command Bar. Floats above the frontmost app (it is
/// invoked by a global shortcut) and paints its own rounded chrome.
final class CommandBarWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            close()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    /// Click-away dismiss (Spotlight behavior). Only fires after the window has
    /// been key, so the open sequence (which *gains* key) never self-closes.
    ///
    /// Deferred for the same reason as `DropdownPanelWindow.resignKey`: closing
    /// inside AppKit's key-change callback over-releases the window.
    override func resignKey() {
        super.resignKey()
        DispatchQueue.main.async { [weak self] in self?.close() }
    }
}

/// Borderless host for the SwiftUI dropdown panel (MeetingBarNG). Behaves
/// like a menu: floats at the pop-up-menu level, closes on Escape and on
/// click-away (`resignKey`), and never appears in the window cycle.
final class DropdownPanelWindow: NSWindow {
    /// Invoked exactly once, just before the window closes, so the coordinator
    /// can record the dismissal (see the toggle suppression in
    /// `openDropdownPanel`). Cleared after firing — `isReleasedWhenClosed` means
    /// the window may be gone immediately after `super.close()`.
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            close()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_: Any?) {
        close()
    }

    /// Click-away dismiss (menu behavior). Only fires after the window has been
    /// key, so the open sequence (which *gains* key) never self-closes.
    ///
    /// The close is deferred to the next run-loop turn ON PURPOSE: closing
    /// synchronously here tears the window down *inside* AppKit's key-change
    /// processing, while AppKit still holds an autoreleased reference to it.
    /// That over-releases the window and crashes with EXC_BAD_ACCESS in
    /// `objc_release` when the autorelease pool drains (seen after a few
    /// open/close cycles).
    override func resignKey() {
        super.resignKey()
        DispatchQueue.main.async { [weak self] in self?.close() }
    }

    override func close() {
        let handler = onClose
        onClose = nil
        handler?()
        super.close()
    }
}

enum DropdownPanelPresentationPolicy {
    /// Menus float above ordinary windows; match that so the panel is never
    /// hidden behind the frontmost app.
    static let level: NSWindow.Level = .popUpMenu

    /// Clicking the status item while the panel is open first resigns key (which
    /// closes the panel) and only then delivers the button's action. Without a
    /// short suppression window that same click would immediately reopen it.
    static let reopenSuppressionInterval: TimeInterval = 0.3
}

enum CommandBarWindowPresentationPolicy {
    static let width: CGFloat = 640
    static let height: CGFloat = 440
    static let contentRect = NSRect(x: 0, y: 0, width: width, height: height)
    static let level: NSWindow.Level = .floating
    /// Fraction of the screen height from the top where the palette centers —
    /// slightly above the middle, like Spotlight.
    static let verticalAnchor: CGFloat = 0.28
}

enum OnboardingWindowPresentationPolicy {
    static let contentRect = NSRect(x: 0, y: 0, width: 760, height: 520)
    static let minimumSize = NSSize(width: 640, height: 460)
    static let styleMask: NSWindow.StyleMask = [.resizable]
    static let level: NSWindow.Level = .normal
    static let isMovableByWindowBackground = true
}

private enum WindowStylePolicy {
    @MainActor
    static func applyRoundedCorners(to window: NSWindow, radius: CGFloat = 12) {
        // Clear, non-opaque window so AppKit derives the drop shadow from the
        // opaque SwiftUI content (which paints its own rounded background and
        // hairline border). A shadow set on the content layer itself can't
        // work here: masksToBounds clips the rounded corners *and* the shadow.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        guard let contentView = window.contentView else { return }

        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = radius
        contentView.layer?.masksToBounds = true
    }
}

/// Owns AppKit window lifecycle for app-level windows.
///
/// Behavior stays outside this type: callers provide closures for close-time
/// decisions such as terminating after incomplete onboarding or marking the
/// changelog as read.
@MainActor
final class WindowCoordinator {
    private weak var preferencesWindow: NSWindow?
    private weak var onboardingHandler: OnboardingHandler?
    private weak var commandBarWindow: NSWindow?
    private weak var calendarWindow: NSWindow?
    private weak var worldClockWindow: NSWindow?
    private weak var eventEditorWindow: NSWindow?
    private weak var cameraPreviewWindow: NSWindow?
    /// Held STRONGLY (and released on the next run-loop turn after close) rather
    /// than self-releasing via `isReleasedWhenClosed`: the panel closes from
    /// inside `resignKey`, and letting AppKit free it there over-released it
    /// (EXC_BAD_ACCESS in `objc_release` on autorelease-pool drain).
    private var dropdownPanel: DropdownPanelWindow?
    private var dropdownPanelClosedAt: Date?

    /// Opens the SwiftUI dropdown panel below the status item, or closes it if
    /// it is already open (toggle). This is the default path
    /// (`Defaults[.useSwiftUIDropdown]` is `true`); the NSMenu is untouched and
    /// remains available as the fallback.
    ///
    /// `anchor` is the status-item button's rect in screen coordinates; the
    /// window is placed by the hostless `DropdownPanelPlacement` so it hangs
    /// under the item and stays inside the screen's visible frame. Like the
    /// Command Bar, the window is self-releasing (`isReleasedWhenClosed`) with no
    /// NSWindowController, so the weak ref nils on close and the next click opens
    /// a fresh panel with a fresh state snapshot.
    func openDropdownPanel(
        state: StatusBarMenuState,
        handlers: DropdownPanelHandlers,
        relativeTo anchor: NSRect
    ) {
        if let existing = dropdownPanel {
            existing.close()
            return
        }
        if let closedAt = dropdownPanelClosedAt,
           Date().timeIntervalSince(closedAt)
           < DropdownPanelPresentationPolicy.reopenSuppressionInterval {
            return
        }

        let window = DropdownPanelWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: DropdownPanelView.preferredWidth,
                height: DropdownPanelView.maximumHeight
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        var resolvedHandlers = handlers
        resolvedHandlers.dismiss = { [weak window] in window?.close() }

        let hosting = NSHostingView(
            rootView: DropdownPanelView(state: state, handlers: resolvedHandlers)
        )
        window.title = ""
        // NOT self-releasing: the coordinator owns the panel and drops it a
        // run-loop turn after close (see `dropdownPanel`), so AppKit is never
        // holding a freed window.
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle]
        window.hidesOnDeactivate = false
        WindowStylePolicy.applyRoundedCorners(to: window, radius: DropdownPanelView.cornerRadius)
        window.level = DropdownPanelPresentationPolicy.level
        window.setFrame(
            DropdownPanelPlacement.frame(
                for: anchor,
                // The hosting view reports the SwiftUI content's height, already
                // clamped by the view's own max height.
                panelSize: NSSize(
                    width: DropdownPanelView.preferredWidth,
                    height: hosting.fittingSize.height
                ),
                screen: visibleFrame(containing: anchor)
            ),
            display: false
        )
        window.onClose = { [weak self] in
            self?.dropdownPanelClosedAt = Date()
            // Release on the NEXT run-loop turn: `onClose` fires from inside
            // `close()`, where AppKit is still using the window. Dropping the
            // last reference there is exactly the over-release that crashed.
            DispatchQueue.main.async { self?.dropdownPanel = nil }
        }

        // LSUIElement accessory app: activate before keying so the panel takes
        // keyboard focus (Escape to dismiss) and accent controls render filled.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        dropdownPanel = window
    }

    /// The visible frame of the screen the status item lives on, falling back to
    /// the main screen (and finally to a sane rect when there is no screen at
    /// all, e.g. in tests).
    private func visibleFrame(containing anchor: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 875)
    }

    /// Opens the month calendar window, or brings it forward if it is already
    /// open. A standard titled/resizable window (like Preferences) held by a
    /// weak ref and reused — no borderless focus fiddliness. The window loads its
    /// own month window of events via the injected handlers; it never touches the
    /// main today/tomorrow sync.
    func openCalendarWindow(handlers: CalendarWindowHandlers) {
        if let calendarWindow {
            if calendarWindow.isMiniaturized {
                calendarWindow.deminiaturize(nil)
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
            calendarWindow.makeKeyAndOrderFront(nil)
            calendarWindow.orderFrontRegardless()
            return
        }

        let viewModel = CalendarGridViewModel(handlers: handlers)
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: CalendarWindowPresentationPolicy.contentRect.width,
                height: CalendarWindowPresentationPolicy.contentRect.height
            ),
            styleMask: [.closable, .titled, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = WindowTitles.calendar
        window.contentView = NSHostingView(rootView: CalendarGridView(viewModel: viewModel))
        window.minSize = CalendarWindowPresentationPolicy.minimumSize

        let controller = NSWindowController(window: window)
        controller.showWindow(self)
        window.center()

        // LSUIElement accessory app: activate before keying so the window opens
        // focused rather than merely ordered to the front.
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        calendarWindow = window
    }

    /// Opens the multi-zone world-clock panel window, or brings it forward if it
    /// is already open. A small standard titled/resizable window held by a weak
    /// ref and reused (like the calendar window). The view reads its zones and
    /// time-format from `Defaults` and refreshes itself each minute, so no
    /// handlers are injected.
    func openWorldClockWindow() {
        if let worldClockWindow {
            if worldClockWindow.isMiniaturized {
                worldClockWindow.deminiaturize(nil)
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
            worldClockWindow.makeKeyAndOrderFront(nil)
            worldClockWindow.orderFrontRegardless()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: WorldClockPanelPresentationPolicy.contentRect.width,
                height: WorldClockPanelPresentationPolicy.contentRect.height
            ),
            styleMask: [.closable, .titled, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = WindowTitles.worldClock
        window.contentView = NSHostingView(rootView: WorldClockPanelView())
        window.minSize = WorldClockPanelPresentationPolicy.minimumSize

        let controller = NSWindowController(window: window)
        controller.showWindow(self)
        window.center()

        // LSUIElement accessory app: activate before keying so the window opens
        // focused rather than merely ordered to the front.
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        worldClockWindow = window
    }

    /// Opens the camera/mic pre-call preview ("mirror check") window, or brings
    /// it forward if already open. A standard titled/resizable window held by a
    /// weak ref, like the calendar window. The `CameraPreviewController` lives in
    /// the SwiftUI view as a `@StateObject`, so the capture session is created
    /// when the window's content is built and — critically — the session is
    /// stopped and the camera released on the view's `onDisappear` (and the
    /// controller's `deinit`) when the window closes, so the camera light turns
    /// off. The coordinator injects the real `dismiss` (close) closure since it
    /// owns the window.
    func openCameraPreviewWindow(handlers: CameraPreviewHandlers) {
        if let cameraPreviewWindow {
            if cameraPreviewWindow.isMiniaturized {
                cameraPreviewWindow.deminiaturize(nil)
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
            cameraPreviewWindow.makeKeyAndOrderFront(nil)
            cameraPreviewWindow.orderFrontRegardless()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: CameraPreviewLayout.contentSize.width,
                height: CameraPreviewLayout.contentSize.height
            ),
            styleMask: [.closable, .titled, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        var resolvedHandlers = handlers
        resolvedHandlers.dismiss = { [weak window] in window?.close() }

        window.title = WindowTitles.cameraPreview
        window.contentView = NSHostingView(rootView: CameraPreviewView(handlers: resolvedHandlers))
        window.minSize = CameraPreviewLayout.minimumSize

        let controller = NSWindowController(window: window)
        controller.showWindow(self)
        window.center()

        // LSUIElement accessory app: activate before keying so the window opens
        // focused rather than merely ordered to the front.
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        cameraPreviewWindow = window
    }

    /// Opens the in-app event editor for `mode` (create or edit). A standard
    /// titled/resizable window (like Preferences) held by a weak ref. Any open
    /// editor is replaced so the form always reflects the requested mode. The
    /// coordinator owns the window, so it injects the real `dismiss` (close)
    /// closure into the handlers before building the view model.
    func openEventEditorWindow(mode: EventEditorMode, handlers: EventEditorHandlers) {
        eventEditorWindow?.close()

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: EventEditorWindowPresentationPolicy.contentRect.width,
                height: EventEditorWindowPresentationPolicy.contentRect.height
            ),
            styleMask: [.closable, .titled, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        var resolvedHandlers = handlers
        resolvedHandlers.dismiss = { [weak window] in window?.close() }
        let viewModel = EventEditorViewModel(mode: mode, handlers: resolvedHandlers)

        window.title = WindowTitles.eventEditor
        window.contentView = NSHostingView(rootView: EventEditorView(viewModel: viewModel))
        window.minSize = EventEditorWindowPresentationPolicy.minimumSize

        let controller = NSWindowController(window: window)
        controller.showWindow(self)
        window.center()

        // LSUIElement accessory app: activate before keying so the editor opens
        // focused rather than merely ordered to the front.
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        eventEditorWindow = window
    }

    /// Opens the Command Bar, or closes it if it's already open (toggle). The
    /// window closes on Escape, on running a row, and on click-away (the window's
    /// `resignKey` override), so it behaves like Spotlight. The window is
    /// self-releasing (isReleasedWhenClosed), so the weak ref nils on close and
    /// the next shortcut press opens a fresh one — no NSWindowController, which
    /// would otherwise keep the reference alive and break the toggle.
    func openCommandBarWindow(handlers: CommandBarHandlers) {
        if let existing = commandBarWindow {
            existing.close()
            return
        }

        let window = CommandBarWindow(
            contentRect: CommandBarWindowPresentationPolicy.contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let viewModel = CommandBarViewModel(
            handlers: handlers,
            dismiss: { [weak window] in window?.close() }
        )
        window.title = ""
        window.isReleasedWhenClosed = true
        window.contentView = NSHostingView(rootView: CommandBarView(viewModel: viewModel))
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle]
        WindowStylePolicy.applyRoundedCorners(to: window)
        window.level = CommandBarWindowPresentationPolicy.level
        positionCommandBar(window)

        // LSUIElement accessory app: activate before keying so the search field
        // gains first-responder focus and accent controls render filled.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        commandBarWindow = window
    }

    private func positionCommandBar(_ window: NSWindow) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else {
            window.center()
            return
        }
        let size = window.frame.size
        let originX = frame.midX - size.width / 2
        let originY = frame.maxY - frame.height * CommandBarWindowPresentationPolicy.verticalAnchor - size.height / 2
        window.setFrameOrigin(NSPoint(x: originX, y: max(frame.minY, originY)))
    }

    func openOnboardingWindow(
        appModel: AppModel,
        onProviderSelected:
            @escaping @MainActor (EventStoreProvider) async -> ProviderSelectionResult,
        onComplete:
            @escaping @MainActor (EventStoreProvider) async -> ProviderSelectionResult
    ) {
        let handler = OnboardingHandler(
            onProviderSelected: onProviderSelected,
            onComplete: onComplete
        )
        handler.appModel = appModel
        onboardingHandler = handler
        let contentView = OnboardingView().environmentObject(handler)
        let onboardingWindow = OnboardingWindow(
            contentRect: OnboardingWindowPresentationPolicy.contentRect,
            styleMask: OnboardingWindowPresentationPolicy.styleMask,
            backing: .buffered,
            defer: false
        )

        onboardingWindow.title = WindowTitles.onboarding
        onboardingWindow.contentView = NSHostingView(rootView: contentView)
        onboardingWindow.minSize = OnboardingWindowPresentationPolicy.minimumSize
        onboardingWindow.isMovableByWindowBackground =
            OnboardingWindowPresentationPolicy.isMovableByWindowBackground
        WindowStylePolicy.applyRoundedCorners(to: onboardingWindow)
        let controller = NSWindowController(window: onboardingWindow)
        controller.showWindow(self)

        // Standard level: onboarding should open focused, but it must not stay
        // above Chrome or other apps during provider authorization.
        onboardingWindow.level = OnboardingWindowPresentationPolicy.level
        onboardingWindow.center()
        // MeetingBar is a menu-bar agent, so it isn't the active app when the
        // setup window opens. Without activating, the window never becomes key
        // until the user clicks it, and prominent (accent) controls render
        // without their fill — making the Continue button look absent.
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow.makeKeyAndOrderFront(nil)
        // `activate` is async for an accessory app, so force initial ordering
        // only once. The standard window level still lets other apps cover it.
        onboardingWindow.orderFrontRegardless()
    }

    func openChangelogWindow() {
        let contentView = ChangelogView()
        let changelogWindow = ChangelogWindow(
            contentRect: ChangelogWindowPresentationPolicy.contentRect,
            styleMask: ChangelogWindowPresentationPolicy.styleMask,
            backing: .buffered,
            defer: false
        )
        changelogWindow.title = WindowTitles.changelog
        changelogWindow.contentView = NSHostingView(rootView: contentView)
        changelogWindow.minSize = ChangelogWindowPresentationPolicy.minimumSize
        changelogWindow.isMovableByWindowBackground = true
        WindowStylePolicy.applyRoundedCorners(to: changelogWindow)

        let controller = NSWindowController(window: changelogWindow)
        controller.showWindow(self)

        // Standard level (not .floating): it shouldn't hover above every app.
        changelogWindow.level = ChangelogWindowPresentationPolicy.level
        changelogWindow.center()
        // Menu-bar agent isn't active; activate so the prominent button renders
        // with its accent fill and the window becomes key.
        NSApp.activate(ignoringOtherApps: true)
        changelogWindow.makeKeyAndOrderFront(nil)
        changelogWindow.orderFrontRegardless()
    }

    func openFullscreenNotificationWindow(event: MBEvent) {
        let screens = NSScreen.screens
        let mouseScreen = screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        let screen = FullscreenNotificationScreenSelectionPolicy.select(
            keyWindowScreen: NSApp.keyWindow?.screen,
            mainWindowScreen: NSApp.mainWindow?.screen,
            mouseScreen: mouseScreen,
            mainScreen: NSScreen.main,
            screens: screens
        )
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)

        let window = FullscreenNotificationWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = NSHostingView(
            rootView: FullscreenNotification(event: event, window: window))
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = .moveToActiveSpace

        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.title = "Meetingbar Fullscreen Notification"
        window.level = .screenSaver

        let controller = NSWindowController(window: window)
        controller.showWindow(self)

        window.setFrame(screenFrame, display: true)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func openPreferencesWindow(
        appModel: AppModel?,
        calendarSync: CalendarSync?
    ) {
        guard let appModel, let calendarSync else { return }
        let contentView = PreferencesShellV2()
            .environmentObject(appModel)
            .environmentObject(calendarSync)

        if let preferencesWindow {
            if preferencesWindow.isMiniaturized {
                preferencesWindow.deminiaturize(nil)
            }
            // Activate the (accessory) app first, then key the existing window,
            // so reopening Preferences brings it to front *and* focused.
            NSApplication.shared.activate(ignoringOtherApps: true)
            preferencesWindow.makeKeyAndOrderFront(nil)
            // `activate` is async for an accessory app, so force the window to
            // the front regardless of when activation lands; otherwise it can
            // be ordered behind other apps' windows.
            preferencesWindow.orderFrontRegardless()
            return
        }

        // Sized so the Dropdown pane — the only one pairing a form with a second
        // full-height column (a 340pt live preview) — opens with both readable.
        // The 240pt sidebar comes off the top of every number here, so the old
        // 900pt default left the form ~319pt: narrower than its own segmented
        // controls, which pushed the preview off the trailing edge. Keep these in
        // step with the `.frame` in `PreferencesShellV2`, or the window and its
        // content disagree about how wide they are allowed to be.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: PreferencesWindowMetrics.defaultSize.width,
                                height: PreferencesWindowMetrics.defaultSize.height),
            styleMask: [.closable, .titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = PreferencesWindowMetrics.minimumSize
        window.maxSize = PreferencesWindowMetrics.maximumSize

        window.title = WindowTitles.preferences
        window.titleVisibility = .visible

        // A real (empty) NSToolbar is what makes the titlebar draw a background.
        // Without one there is nothing for AppKit to render behind the title, so
        // with a transparent titlebar the pane's Form scrolled straight up into
        // bare window and collided with the title text.
        //
        // Deliberately the platform's own chrome rather than a hand-built blurred
        // header: AppKit then draws whatever the running OS considers current —
        // standard material on macOS 15, Liquid Glass on 26 — and supplies the
        // scroll-edge effect for free. A hand-rolled `.ultraThinMaterial` strip
        // would be frozen at one OS's look and read as wrong on the others.
        //
        // `.unified` merges titlebar and toolbar into the single bar the sidebar
        // sits under, which is the System Settings shape this window is copying.
        let toolbar = NSToolbar(identifier: "MeetingBarNGPreferences")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = false

        // NSHostingController (not NSHostingView) applies the window's safe
        // area regions to the SwiftUI content. safeAreaRegions = .all makes
        // NavigationSplitView receive the title-bar safe-area inset, so the
        // sidebar List clears the traffic lights and the detail column's Form
        // gets a properly bounded scroll height. NSHostingView does NOT
        // propagate safe areas, which is why NavigationSplitView clipped.
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.safeAreaRegions = .all
        window.contentViewController = hostingController

        // MUST come after assigning the content view controller. Doing so makes
        // AppKit adopt the controller's fitting size, and a SwiftUI `.frame`
        // carrying only min/max resolves its fitting width to the MINIMUM — so
        // the `contentRect` above was silently discarded and Preferences opened
        // at its smallest allowed size, narrow enough that the Dropdown pane
        // dropped its preview on every launch.
        window.setContentSize(PreferencesWindowMetrics.defaultSize)

        // Standard window level (not .floating): clicking another app should
        // send Preferences behind it, like any normal window.

        let controller = NSWindowController(window: window)
        controller.showWindow(self)
        window.center()

        // This is an LSUIElement accessory app, so it isn't frontmost by
        // default. Activate the app *before* keying the window so Preferences
        // opens focused rather than just ordered to the front.
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // `activate` is async for an accessory app, so force the window to the
        // front regardless of when activation lands; otherwise it can open
        // behind other apps' windows.
        window.orderFrontRegardless()

        preferencesWindow = window
    }

    func handleWindowClosed(
        _ window: NSWindow?,
        onboardingCompleted: Bool,
        onIncompleteOnboardingClosed: () -> Void,
        onChangelogClosed: () -> Void
    ) {
        handleWindowClosed(
            title: window?.title,
            onboardingCompleted: onboardingCompleted,
            onIncompleteOnboardingClosed: onIncompleteOnboardingClosed,
            onChangelogClosed: onChangelogClosed
        )
    }

    func handleWindowClosed(
        title windowTitle: String?,
        onboardingCompleted: Bool,
        onIncompleteOnboardingClosed: () -> Void,
        onChangelogClosed: () -> Void
    ) {
        guard let windowTitle else { return }

        if windowTitle == WindowTitles.onboarding, !onboardingCompleted {
            onIncompleteOnboardingClosed()
        } else if windowTitle == WindowTitles.changelog {
            onChangelogClosed()
        }
    }
}
