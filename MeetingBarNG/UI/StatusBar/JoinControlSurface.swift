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

/// A raised, lit control surface — fill, a top-lit rim, and a tight shadow.
///
/// NOT SwiftUI's `glassEffect`, and that is a finding rather than an oversight.
/// `WindowCoordinator`'s `PanelBackdrop` documents why the panel's own
/// translucency is an AppKit `NSGlassEffectView`: SwiftUI's materials inside an
/// `NSHostingView` over a borderless transparent window blend WITHIN the window,
/// so they sample nothing and composite over emptiness. A `glassEffect` capsule
/// in here renders as a flat dark pill — verified by screenshot, which is the
/// only way to tell, since it compiles and "works" either way.
///
/// The three cues below are what actually reads as glass on this surface, and
/// they are the same ones `DaySummaryHeaderButton` uses. They have to travel
/// together: a fill alone is a swatch, a border alone is a boxed icon, and
/// neither alone lifts the control off the panel.
///
/// This is also the opposite call from `PanelCard`, which stays flat, and the
/// difference is size rather than inconsistency: a large surface stacking
/// translucency accumulates haze, while a control small enough to read as a lens
/// is exactly what the treatment is for.
struct JoinControlSurface: ViewModifier {
    /// Whether the meeting is close enough to act on. Drives the tint, not the
    /// presence of the treatment — a Join button is a button either way.
    let isActionImminent: Bool

    func body(content: Content) -> some View {
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
