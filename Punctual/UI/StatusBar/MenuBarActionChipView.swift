//
//  MenuBarActionChipView.swift
//  MeetingBarNG
//
//  Draws the capsule around the menu bar's Join label. The WHERE is decided by
//  the hostless `MenuBarActionChipGeometry`; this file only turns that rect into
//  pixels.
//
//  An overlay on the status-item button, for the same reason
//  `MeetingProgressOverlayView` is one: AppKit renders the item's title and owns
//  everything that makes it look native — light/dark adaptation, the inversion
//  while the panel is open, accessibility. Re-rendering the item ourselves to put
//  a capsule behind the word "Join" would mean reimplementing all of that. So the
//  capsule is drawn over the top and kept light enough to read through, and the
//  text underneath stays AppKit's.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import AppKit

enum MenuBarActionChipMetricsStyle {
    /// `labelColor`, not the accent colour, for the reason spelled out in
    /// `MeetingProgressStyleMetrics.fillColor`: the menu bar's tint comes from
    /// the user's wallpaper and can sit anywhere, including on top of their
    /// accent. macOS already guarantees the bar's own text is legible against
    /// whatever is behind it, so drawing in that colour inherits the guarantee.
    static let color: NSColor = .labelColor
    /// Faint enough to read the label through. The interior is a hint that this
    /// is a container; the border is what says "control".
    static let fillAlpha: CGFloat = 0.12
    static let borderAlpha: CGFloat = 0.45
    static let borderWidth: CGFloat = 1
}

/// A transparent overlay that strokes the Join chip's capsule.
final class MenuBarActionChipOverlayView: NSView {
    /// The capsule to draw, in this view's coordinates, or `nil` for no chip.
    var chipRect: CGRect? {
        didSet { if chipRect != oldValue { needsDisplay = true } }
    }

    /// Clicks belong to the status item underneath. The chip is not a real
    /// control — `StatusBarItemController` hit-tests the same rect on the
    /// button's own click — and an overlay that swallowed the event would stop
    /// the menu bar item opening the panel at all.
    override func hitTest(_: NSPoint) -> NSView? { nil }

    override var isFlipped: Bool { false }

    override func draw(_: NSRect) {
        guard let chipRect, !chipRect.isEmpty else { return }

        let radius = chipRect.height / 2
        let capsule = NSBezierPath(roundedRect: chipRect, xRadius: radius, yRadius: radius)

        MenuBarActionChipMetricsStyle.color
            .withAlphaComponent(MenuBarActionChipMetricsStyle.fillAlpha).setFill()
        capsule.fill()

        capsule.lineWidth = MenuBarActionChipMetricsStyle.borderWidth
        MenuBarActionChipMetricsStyle.color
            .withAlphaComponent(MenuBarActionChipMetricsStyle.borderAlpha).setStroke()
        capsule.stroke()
    }
}
