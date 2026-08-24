//
//  PanelTheme+MeetingBar.swift
//  MeetingBarNG
//
//  Adapter turning the hostless `PanelTheme` choices into the AppKit and SwiftUI
//  values that actually paint. Kept out of the hostless module, which cannot
//  import AppKit or SwiftUI.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import AppKit
import SwiftUI

extension PanelAppearance {
    /// The AppKit appearance to pin the panel window to, or `nil` to leave it
    /// following the system.
    ///
    /// Set on the WINDOW rather than via SwiftUI's `preferredColorScheme`: the
    /// panel's backdrop is an AppKit vibrancy view composited by the window
    /// server, and a SwiftUI-level colour scheme would restyle the content while
    /// leaving the material behind it in the system appearance.
    var nsAppearance: NSAppearance? {
        switch PanelThemePolicy.forcedAppearance(self) {
        case nil: return nil
        case .light: return NSAppearance(named: .vibrantLight)
        case .dark: return NSAppearance(named: .vibrantDark)
        case .system: return nil  // Unreachable: forcedAppearance never returns it.
        }
    }

    var localizedNameKey: String {
        switch self {
        case .system: "preferences_theme_appearance_system"
        case .light: "preferences_theme_appearance_light"
        case .dark: "preferences_theme_appearance_dark"
        }
    }
}

extension PanelAccent {
    /// The colour to tint the panel with, or `nil` to inherit the system accent.
    ///
    /// Mapped to the system colours rather than literal RGB so each one keeps its
    /// own light/dark variants and its Increase Contrast treatment — a hardcoded
    /// hex would look right in exactly one appearance.
    var tint: Color? {
        switch self {
        case .system: return nil
        case .blue: return Color(nsColor: .systemBlue)
        case .purple: return Color(nsColor: .systemPurple)
        case .pink: return Color(nsColor: .systemPink)
        case .red: return Color(nsColor: .systemRed)
        case .orange: return Color(nsColor: .systemOrange)
        case .yellow: return Color(nsColor: .systemYellow)
        case .green: return Color(nsColor: .systemGreen)
        case .graphite: return Color(nsColor: .systemGray)
        }
    }

    var localizedNameKey: String {
        switch self {
        case .system: "preferences_theme_accent_system"
        case .blue: "preferences_theme_accent_blue"
        case .purple: "preferences_theme_accent_purple"
        case .pink: "preferences_theme_accent_pink"
        case .red: "preferences_theme_accent_red"
        case .orange: "preferences_theme_accent_orange"
        case .yellow: "preferences_theme_accent_yellow"
        case .green: "preferences_theme_accent_green"
        case .graphite: "preferences_theme_accent_graphite"
        }
    }
}
