//
//  PanelChrome.swift
//  MeetingBarNG
//
//  The panel's shared edge treatment.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import SwiftUI

enum PanelChrome {
    /// A lit rim for a raised surface — cards, buttons, chips.
    ///
    /// Appearance-aware, which the four hand-written copies of this gradient were
    /// NOT: they all used `Color.white.opacity(...)`, which is invisible on a
    /// light surface. That went unnoticed because the panel is usually dark, so
    /// the bug only showed in light appearance.
    ///
    /// The two appearances need different physics, not the same colour flipped.
    /// On a dark surface the top edge catches light and fades by the bottom. On a
    /// light one there is no light to catch — what reads as an edge is a soft
    /// shadow line, strongest at the top where the surface would occlude itself.
    /// Both are "stronger at the top", for opposite reasons.
    static func rim(
        _ scheme: ColorScheme,
        top: Double = 0.20,
        bottom: Double = 0.06
    ) -> LinearGradient {
        let base: Color = scheme == .dark ? .white : .black
        // A dark edge does its job at lower opacity than a light one; matching
        // the numbers would draw a hard outline in light appearance.
        let scale = scheme == .dark ? 1.0 : 0.7
        return LinearGradient(
            colors: [base.opacity(top * scale), base.opacity(bottom * scale)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
