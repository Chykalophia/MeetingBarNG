//
//  JoinControlSurface.swift
//  MeetingBarNG
//
//  The one background the panel's Join controls wear — the meeting card's button
//  and the agenda rows' hover pill. Shared so the two cannot drift; they are the
//  same affordance at two sizes.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import SwiftUI

/// Real Liquid Glass on macOS 26; a drawn imitation of it below.
///
/// The imitation existed on BOTH paths for a while because a `glassEffect`
/// capsule here rendered as a flat dark pill. The cause was not SwiftUI: the
/// panel was wrapped in an AppKit `NSGlassEffectView`, and per WWDC25 session
/// 310 "glass can't directly sample other glass" — the inner capsule sampled the
/// outer glass, found nothing to refract, and collapsed. Removing that wrapper
/// (see `PanelBackdrop`) is what let the real thing work.
///
/// The macOS 15 branch keeps the drawn version: fill, a top-lit rim, and a tight
/// shadow, the same three cues `DaySummaryHeaderButton` uses. They have to travel
/// together — a fill alone is a swatch, a border alone is a boxed icon, and
/// neither alone lifts the control off the panel.
struct JoinControlSurface: ViewModifier {
    /// Whether the meeting is close enough to act on. Drives the tint, not the
    /// presence of the treatment — a Join button is a button either way.
    let isActionImminent: Bool

    /// Drawn on every version, because SwiftUI's `glassEffect` cannot render
    /// here — measured, not assumed. It samples WITHIN the window, and this
    /// panel's surface is an AppKit `NSVisualEffectView` that is not part of
    /// SwiftUI's render tree, so a glass capsule finds nothing to refract and
    /// composites to a flat fill. Screenshotted over both an `NSGlassEffectView`
    /// and a `.menu` vibrancy backdrop; flat both times.
    ///
    /// It DOES work over a plain clear window with a SwiftUI-drawn glass panel —
    /// but that surface cannot reach a real menu's density, so the panel would
    /// win glassy buttons at the cost of looking unlike a macOS menu. The trade
    /// is recorded in docs/DROPDOWN-MODERNIZATION.md §7.
    func body(content: Content) -> some View {
        drawnGlass(content)
    }

    private func drawnGlass(_ content: Content) -> some View {
        content
            .background(
                Capsule().fill(
                    // Muted rather than merely translucent when the meeting is
                    // still a way off: fading white-on-accent goes muddy, whereas
                    // a lit, recessed fill still reads as a button — available,
                    // simply not urgent.
                    isActionImminent
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(Color.primary.opacity(0.10))
                )
            )
            .overlay(
                // Light from above: bright along the top edge, gone by the
                // bottom. A uniform border would flatten the control back out.
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isActionImminent ? 0.45 : 0.24),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
            )
            // Sits ON the panel rather than in it. Tight and low-opacity: a wider
            // shadow smears across the glass behind it.
            .shadow(color: .black.opacity(isActionImminent ? 0.32 : 0.22), radius: 2, y: 1)
    }
}

extension View {
    /// Applies the panel's shared Join-control background.
    func joinControlSurface(isActionImminent: Bool) -> some View {
        modifier(JoinControlSurface(isActionImminent: isActionImminent))
    }
}
