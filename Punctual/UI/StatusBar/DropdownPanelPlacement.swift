//
//  DropdownPanelPlacement.swift
//  MeetingBarNG
//
//  Hostless placement math for the custom SwiftUI dropdown panel. Pure geometry
//  only — no AppKit/SwiftUI/Defaults — so the "hangs below the status item and
//  never renders offscreen" guarantee is unit-testable without a window server.
//  The host (`WindowCoordinator.openDropdownPanel`) supplies the status-item
//  rect in screen coordinates and the screen's visible frame.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import CoreGraphics

/// Where the dropdown panel's window goes, in AppKit screen coordinates
/// (bottom-left origin, y increasing upwards).
enum DropdownPanelPlacement {
    /// Breathing room kept between the panel and the edges of the visible frame.
    static let screenEdgeInset: CGFloat = 8

    /// Gap between the bottom of the status-item button and the top of the panel.
    static let statusItemGap: CGFloat = 4

    /// Floor applied when the space below the status item is unusably small
    /// (tiny/rotated displays); the panel's own ScrollView takes over from there.
    static let minimumHeight: CGFloat = 160

    /// The panel frame for a status item at `anchor` (its button rect in screen
    /// coordinates) on the screen whose visible frame is `screen`.
    ///
    /// - Hangs directly below the anchor, horizontally centered on it.
    /// - Clamps to the visible frame's left/right edges, so a status item at the
    ///   far right (the usual case) never pushes the panel offscreen.
    /// - Trims the height to the room above the visible frame's bottom edge, so a
    ///   long day scrolls inside the panel instead of running off the screen.
    static func frame(for anchor: CGRect, panelSize: CGSize, screen: CGRect) -> CGRect {
        let height = resolvedHeight(panelHeight: panelSize.height, anchor: anchor, screen: screen)
        let top = anchor.minY - statusItemGap
        let originY = max(screen.minY + screenEdgeInset, top - height)

        let centered = anchor.midX - panelSize.width / 2
        let rightLimit = screen.maxX - screenEdgeInset - panelSize.width
        let originX = max(screen.minX + screenEdgeInset, min(centered, rightLimit))

        return CGRect(x: originX, y: originY, width: panelSize.width, height: height)
    }

    /// The panel height once trimmed to the space between the status item and the
    /// bottom of the visible frame, never below `minimumHeight` (or the panel's
    /// own height, when the content is shorter than that floor).
    static func resolvedHeight(
        panelHeight: CGFloat,
        anchor: CGRect,
        screen: CGRect
    ) -> CGFloat {
        let available = anchor.minY - statusItemGap - (screen.minY + screenEdgeInset)
        guard available < panelHeight else { return panelHeight }
        return max(available, min(panelHeight, minimumHeight))
    }
}
