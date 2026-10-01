//
//  PanelTheme.swift
//  MeetingBarNG
//
//  The dropdown panel's theme: which appearance it forces, and which accent it
//  paints with.
//
//  Deliberately TWO axes and nothing more. A theme system that owns every colour
//  in the panel would have to re-answer, per theme, every contrast decision
//  already settled in DROPDOWN-MODERNIZATION §1 — the glass layer, the card
//  fills, the muted/bright Join threshold. Appearance and accent are the two
//  choices that change how the panel feels without reopening any of that, and
//  both are things macOS already knows how to render correctly.
//
//  Hostless: the enums and their lenient decoding. Turning an accent into an
//  actual colour is the app target's business.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Foundation

/// Which appearance the panel forces on itself.
public enum PanelAppearance: String, CaseIterable, Sendable {
    /// Follow the system. The default, and the only value that keeps the panel
    /// changing with the user's schedule.
    case system
    case light
    case dark
}

/// Which accent the panel paints with.
///
/// The list is the macOS system accents, not an arbitrary palette: they are the
/// colours the OS already guarantees are legible on both appearances, and they
/// are the ones a user has already chosen between once in System Settings.
public enum PanelAccent: String, CaseIterable, Sendable {
    /// Inherit the system accent. The default.
    case system
    case blue
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case graphite

    /// Whether this overrides the system accent at all.
    public var overridesSystem: Bool { self != .system }
}

public enum PanelThemePolicy {
    /// Decodes a stored appearance, falling back to `.system`.
    ///
    /// Lenient on purpose, matching how `dropdownDensity` is read: an unknown
    /// value from an older build or a hand-edited plist should cost the user
    /// their theme, not leave the panel unable to draw.
    public static func appearance(fromRaw raw: String) -> PanelAppearance {
        PanelAppearance(rawValue: raw) ?? .system
    }

    /// Decodes a stored accent, falling back to `.system`.
    public static func accent(fromRaw raw: String) -> PanelAccent {
        PanelAccent(rawValue: raw) ?? .system
    }

    /// Whether the panel should override the window's appearance at all.
    ///
    /// `nil` means "leave the window alone", which is NOT the same as forcing
    /// light: a window with no explicit appearance follows the system as it
    /// changes, and pinning it to whatever the system happened to be at launch
    /// would freeze it there until the next relaunch.
    public static func forcedAppearance(_ appearance: PanelAppearance) -> PanelAppearance? {
        appearance == .system ? nil : appearance
    }
}
