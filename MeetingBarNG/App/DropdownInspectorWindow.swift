//
//  DropdownInspectorWindow.swift
//  MeetingBarNG
//
//  DEBUG-only development aid: hosts the real dropdown panel in a window that
//  STAYS OPEN, so the panel can be screenshotted and inspected from another
//  process.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

#if DEBUG
import AppKit

/// A dropdown panel that does not dismiss itself.
///
/// The real `DropdownPanelWindow` closes the instant anything else takes focus —
/// correct for a menu, and fatal for inspecting it, since `screencapture` (and
/// any other tool driving the app from outside) takes focus by existing. The
/// `debugPinDropdownPanel` default was an attempt to suppress that dismissal in
/// place; this is the replacement, and it works because the panel it opens was
/// never a menu to begin with.
///
/// Deliberately borderless rather than titled, even though a titled window would
/// come with a close button: the whole point is to look at the panel's own
/// surface — corner radius, glass rim, shadow, backdrop blend — and a titlebar
/// would either cover the header or change the rounding being judged. What you
/// see here is pixel-for-pixel what a click on the status item draws.
///
/// Dismissal, since there is no close button: Escape, or re-running the deep
/// link (it toggles).
final class DropdownInspectorWindow: NSWindow {
    /// Fires just before close so the coordinator can drop its reference.
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

    // NOTE: no `resignKey` override. That omission IS the feature — losing focus
    // leaves this window on screen.

    override func close() {
        let handler = onClose
        onClose = nil
        handler?()
        super.close()
    }

    /// Whether `url` is the inspector's deep link (`meetingbar://dropdown-debug`).
    ///
    /// Matched here rather than in `URLHandler` on purpose: routing through
    /// `AppRoute` would put a DEBUG-only case in an enum the release build also
    /// compiles, and thread a DEBUG-only closure through `AppEnvironment`. A
    /// development hook should not leave a shape behind in shipping types.
    static func matches(_ url: URL) -> Bool {
        url.scheme == "meetingbar" && url.host == "dropdown-debug"
    }
}

/// Everything needed to host the real dropdown panel in the inspector window.
struct DropdownInspectorSnapshot {
    let state: StatusBarMenuState
    let handlers: DropdownPanelHandlers
    /// The live status-item rect when there is one, so the panel lands where a
    /// click would put it. `nil` falls back to a synthetic top-right anchor.
    let anchor: NSRect?
}

enum DropdownInspectorPresentationPolicy {
    /// Above ordinary windows so a screenshot cannot catch it behind something,
    /// but below `.popUpMenu` — a real menu opened during inspection should still
    /// win, the same way it would over the real panel.
    static let level: NSWindow.Level = .floating

    /// Where the inspector hangs when there is no status item to anchor to: the
    /// top-right corner of the screen, which is where the status item would be.
    /// Sized as a zero-width rect at the menu-bar line so the shared placement
    /// math treats it exactly like a real status-item anchor.
    static func syntheticAnchor(in screenFrame: NSRect) -> NSRect {
        NSRect(x: screenFrame.maxX - 80, y: screenFrame.maxY, width: 0, height: 0)
    }
}
#endif
