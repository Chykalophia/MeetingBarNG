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
        #if DEBUG
        // Development aid: the panel dismisses the instant anything else takes
        // focus, which makes it impossible to screenshot or inspect from another
        // process. Holding it open needs a switch that survives a NORMAL launch —
        // an environment variable does not, because `open` launches the app
        // bundle through LaunchServices rather than inheriting the caller's
        // environment, and running the executable directly skips the bundle so
        // the status item never appears.
        //
        //   defaults write com.chykalophia.MeetingBarNG debugPinDropdownPanel -bool true
        //
        // DEBUG-only: it defeats the panel's defining behaviour, so it must be
        // unreachable in a release build.
        if Self.isPinnedForDebugging { return }
        #endif
        DispatchQueue.main.async { [weak self] in self?.close() }
    }

    override func close() {
        let handler = onClose
        onClose = nil
        handler?()
        super.close()
    }

    #if DEBUG
    /// Read once per launch: a screenshot run sets the key before launching, and
    /// re-reading it on every focus change would be a defaults hit per keystroke.
    static let isPinnedForDebugging = UserDefaults.standard.bool(
        forKey: "debugPinDropdownPanel"
    )
    #endif
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

/// The dropdown panel's translucent surface on macOS 15–25.
///
/// SwiftUI's `.regularMaterial` inside an `NSHostingView` blends WITHIN the
/// window. Over a borderless transparent window that means sampling nothing, so
/// the panel composited over emptiness and read as flat. Desktop translucency
/// there needs an AppKit surface with `.behindWindow` blending, which is what
/// this builds.
///
/// On macOS 26 it builds nothing: Liquid Glass is drawn by SwiftUI and an AppKit
/// wrapper actively prevents it. See `wrap(_:radius:)`.
private enum PanelBackdrop {
    @MainActor
    static func wrap(_ content: NSView, radius: CGFloat) -> NSView {
        // Deliberately NOT `NSGlassEffectView`, on any version.
        //
        // Two things were learned the hard way here, both by screenshot:
        //
        // 1. Wrapping the hosting view in `NSGlassEffectView` broke every
        //    `glassEffect` INSIDE the panel. WWDC25 session 310, verbatim:
        //    "glass can't directly sample other glass" — an inner glass control
        //    sitting inside the outer glass samples glass, finds nothing to
        //    refract, and collapses to a flat fill.
        // 2. Removing it and letting SwiftUI draw the panel's own glass did fix
        //    the controls, but the surface came out far too clear: compared side
        //    by side against a real NSMenu over the same wallpaper, colour
        //    streaks from the desktop read straight across the agenda.
        //
        // `.menu` material is the answer to both. It is the material AppKit
        // gives real menus, so the density matches native by construction rather
        // than by a tint constant someone has to keep re-tuning.
        let effect = NSVisualEffectView()
        // `.menu` rather than `.popover`: this IS a menu, and the material
        // carries the vibrancy AppKit gives real menus.
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        // Rounded by MASK IMAGE, not by a layer corner radius. A vibrancy
        // material is composited by the window server, which does not respect
        // `masksToBounds` — on macOS 26 that left opaque white squares in the
        // corners where the square material outran the rounded layer. The mask
        // image is the supported way to shape one, and it clips the material
        // itself rather than a layer drawn from it.
        effect.maskImage = roundedMask(radius: radius)

        content.frame = effect.bounds
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        return effect
    }

    /// A resizable rounded-rectangle mask.
    ///
    /// Cap insets make it nine-part: the corners keep their radius at any size
    /// while the edges stretch, so one small image masks the whole panel however
    /// tall the day makes it.
    @MainActor
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(
            size: NSSize(width: edge, height: edge),
            flipped: false
        ) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: radius,
            left: radius,
            bottom: radius,
            right: radius
        )
        image.resizingMode = .stretch
        return image
    }
}

private enum WindowStylePolicy {
    @MainActor
    /// - Parameter roundsContentView: pass `false` when the content view is a
    ///   backdrop that already owns its rounding (`PanelBackdrop`). Layer-masking
    ///   an `NSGlassEffectView` shears off the specular rim it draws just outside
    ///   its own bounds, which is the difference between glass and a grey box.
    static func applyRoundedCorners(
        to window: NSWindow,
        radius: CGFloat = 12,
        roundsContentView: Bool = true
    ) {
        // Clear, non-opaque window so AppKit derives the drop shadow from the
        // opaque SwiftUI content (which paints its own rounded background and
        // hairline border). A shadow set on the content layer itself can't
        // work here: masksToBounds clips the rounded corners *and* the shadow.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        guard roundsContentView, let contentView = window.contentView else { return }

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
    /// Key AppKit stores the Preferences window's frame under. Changing it
    /// silently discards everyone's saved geometry, so it is pinned here rather
    /// than written inline at the call site.
    static let preferencesFrameAutosaveName = "MeetingBarNGPreferencesWindow"

    /// Whether the dropdown panel is currently on screen. Lets a deep link
    /// open the panel IDEMPOTENTLY: `openDropdownPanel` toggles, which is right
    /// for a status-item click and wrong for "meetingbar://dropdown", where a
    /// second invocation should leave it open rather than dismiss it.
    var isDropdownPanelOpen: Bool { dropdownPanel != nil }

    private weak var preferencesWindow: NSWindow?

    /// Live move/resize observers for the Preferences window. Held so a second
    /// open cannot stack a duplicate set on top of the first.
    private var preferencesFrameObservers: [NSObjectProtocol] = []
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

    #if DEBUG
    /// Held for the same reason as `dropdownPanel`, and released the same way.
    private var dropdownInspector: DropdownInspectorWindow?
    #endif

    /// Opens the SwiftUI dropdown panel below the status item, or closes it if
    /// it is already open (toggle).
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

        window.title = ""
        // NOT self-releasing: the coordinator owns the panel and drops it a
        // run-loop turn after close (see `dropdownPanel`), so AppKit is never
        // holding a freed window.
        window.isReleasedWhenClosed = false
        let contentHeight = installDropdownPanelSurface(
            in: window,
            state: state,
            handlers: resolvedHandlers
        )
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.level = DropdownPanelPresentationPolicy.level
        window.setFrame(
            DropdownPanelPlacement.frame(
                for: anchor,
                panelSize: NSSize(
                    width: DropdownPanelView.preferredWidth,
                    height: contentHeight
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

    /// Installs the panel's visible surface into `window` and reports the height
    /// the SwiftUI content wants (already clamped by the view's own maximum).
    ///
    /// Shared by the real panel and the DEBUG inspector so what gets inspected
    /// cannot drift from what ships — the backdrop, corner radius and shadow are
    /// built in exactly one place.
    @discardableResult
    private func installDropdownPanelSurface(
        in window: NSWindow,
        state: StatusBarMenuState,
        handlers: DropdownPanelHandlers
    ) -> CGFloat {
        let hosting = NSHostingView(
            rootView: DropdownPanelView(state: state, handlers: handlers)
        )
        // The hosting view goes INSIDE a vibrancy/glass backdrop rather than being
        // the content view itself — see `PanelBackdrop` for why SwiftUI's own
        // material cannot do this job here.
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        window.contentView = PanelBackdrop.wrap(
            hosting,
            radius: DropdownPanelView.cornerRadius
        )
        // The shadow is derived from the content's alpha. With a translucent
        // backdrop that derivation has to be redone AFTER the content is in
        // place, or AppKit keeps a shadow shaped like the window's square frame.
        window.invalidateShadow()
        WindowStylePolicy.applyRoundedCorners(
            to: window,
            radius: DropdownPanelView.cornerRadius,
            roundsContentView: false
        )
        return hosting.fittingSize.height
    }

    #if DEBUG
    /// Opens the dropdown panel in a window that stays put, or closes it if it is
    /// already up (toggle, so the same deep link both shows and hides it).
    ///
    /// Development aid only — see `DropdownInspectorWindow`. `anchor` is the real
    /// status-item rect when the caller has one, so the panel lands where a click
    /// would put it; `nil` falls back to the top-right of the main screen.
    func toggleDropdownInspectorWindow(
        state: StatusBarMenuState,
        handlers: DropdownPanelHandlers,
        anchor: NSRect?
    ) {
        if let existing = dropdownInspector {
            existing.close()
            return
        }

        let window = DropdownInspectorWindow(
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

        window.title = ""
        window.isReleasedWhenClosed = false
        let contentHeight = installDropdownPanelSurface(
            in: window,
            state: state,
            handlers: resolvedHandlers
        )
        // Movable, unlike the real panel: dragging it off a busy desktop is often
        // the fastest way to see how the glass reads over a different backdrop.
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.level = DropdownInspectorPresentationPolicy.level

        let screen = visibleFrame(containing: anchor ?? .zero)
        let resolvedAnchor = anchor
            ?? DropdownInspectorPresentationPolicy.syntheticAnchor(in: screen)
        window.setFrame(
            DropdownPanelPlacement.frame(
                for: resolvedAnchor,
                panelSize: NSSize(
                    width: DropdownPanelView.preferredWidth,
                    height: contentHeight
                ),
                screen: screen
            ),
            display: false
        )
        window.onClose = { [weak self] in
            DispatchQueue.main.async { self?.dropdownInspector = nil }
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        dropdownInspector = window
    }
    #endif

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

        // Restore where and how big the user left it. Order matters: the default
        // size above establishes FIRST-launch geometry, and this overwrites it
        // only when a saved frame actually exists — `setFrameUsingName` reports
        // whether it restored anything, so a first run falls through to `center()`
        // at the default size rather than being centred on top of a restore that
        // never happened.
        //
        // Paired with the explicit `saveFrame(usingName:)` in
        // `handleWindowClosed`; see the note there for why the save is not left to
        // `setFrameAutosaveName`. `minSize`/`maxSize` still apply, so a frame
        // saved by an older build outside the current range is clamped rather
        // than honoured.
        // Save on every move and resize, not only on close. The close path needs
        // the app to shut down cleanly, and a crash — or a force-quit — would
        // otherwise throw away the geometry the user had just set. These fire
        // only while a window is actually being dragged, so the cost is nothing,
        // and it keeps the saved frame correct at all times rather than only
        // after a well-behaved exit.
        //
        // Registered BEFORE the restore below so the `center()` fallback is
        // itself persisted: otherwise a first run saves nothing until the user
        // happens to drag the window.
        //
        // The stored reference has to be live before then too — the observers
        // read the window back off it, and it used to be assigned only at the end
        // of this method, by which time `center()` had already fired against a
        // nil one.
        preferencesWindow = window
        preferencesFrameObservers.forEach(NotificationCenter.default.removeObserver)
        preferencesFrameObservers = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification
        ].map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            // Reads the window back off `self` rather than out of the
            // notification: `Notification` is not `Sendable`, so carrying it into
            // the MainActor closure is a data race the compiler rejects, whereas
            // this @MainActor class is.
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.preferencesWindow?
                        .saveFrame(usingName: Self.preferencesFrameAutosaveName)
                }
            }
        }

        if !window.setFrameUsingName(Self.preferencesFrameAutosaveName) {
            window.center()
            // Persist the first-run geometry immediately rather than waiting for
            // the user to move the window. Without this the very first session
            // has nothing saved, so a crash before any drag loses the placement.
            window.saveFrame(usingName: Self.preferencesFrameAutosaveName)
        }

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
        // Persist Preferences' geometry HERE rather than relying on
        // `setFrameAutosaveName`. That was tried first and wrote nothing: AppKit's
        // implicit save never fired for this window, even across a graceful quit,
        // so the user's size silently reset every launch. `saveFrame(usingName:)`
        // and `setFrameUsingName(_:)` are a matched pair over the same defaults
        // key, and calling the save explicitly on close makes it deterministic.
        if let window, window === preferencesWindow {
            window.saveFrame(usingName: Self.preferencesFrameAutosaveName)
        }

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
