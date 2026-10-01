//
//  ReleaseNotes.swift
//  MeetingBar
//
//  Copyright © 2026 Peter Krzyzek / Chykalophia. All rights reserved.
//
//  Structured "What's New" data model for MeetingBarNG. Each release is a set
//  of categorized highlights; the category drives an SF Symbol + accent color
//  in ChangelogView. Entry text stays plain English (not localized), matching
//  the original per-version changelog behavior — only the surrounding chrome
//  is localized.
//

import SwiftUI

/// Category of a single changelog highlight. Drives its icon + tint.
enum ChangeKind {
    case feature
    case improvement
    case fix
    case localization

    /// SF Symbol shown at the leading edge of the row.
    var symbolName: String {
        switch self {
        case .feature: "sparkles"
        case .improvement: "wrench.and.screwdriver.fill"
        case .fix: "checkmark.seal.fill"
        case .localization: "globe"
        }
    }

    /// Accent color the symbol is tinted with.
    var accentColor: Color {
        switch self {
        case .feature: .purple
        case .improvement: .orange
        case .fix: .green
        case .localization: .blue
        }
    }

    /// Localization key for the row's accessibility label. The view resolves it
    /// via `.loco()`; keeping the raw key here leaves the model free of I18N.
    var accessibilityLabelKey: String {
        switch self {
        case .feature: "changelog_kind_feature"
        case .improvement: "changelog_kind_improvement"
        case .fix: "changelog_kind_fix"
        case .localization: "changelog_kind_localization"
        }
    }
}

/// One highlight line within a release. `text` is plain English by design.
struct ChangeEntry {
    let kind: ChangeKind
    let text: String
}

/// A single released version and its highlights.
struct ReleaseNote: Identifiable {
    /// Semantic version string, e.g. "0.1.0". Also serves as the identity.
    let version: String
    /// Preformatted display date (e.g. "July 2026"), or nil to omit. Stored as
    /// a static string so the module never calls `Date()` at load time.
    let date: String?
    let highlights: [ChangeEntry]

    var id: String { version }
}

/// Namespace for the seeded release data plus pure filtering helpers.
enum ReleaseNotes {
    /// All shipped releases, newest first. MeetingBarNG resets the changelog to
    /// a single debut entry; the legacy upstream 3.x–5.0 notes are intentionally
    /// dropped.
    static let all: [ReleaseNote] = [
        ReleaseNote(
            version: "1.1.0",
            date: "October 2026",
            highlights: [
                ChangeEntry(
                    kind: .feature,
                    text: "Punctual now updates itself. Choose automatic checks and installs, or check "
                        + "by hand, in Preferences ▸ About ▸ Updates or from the right-click menu."
                ),
                ChangeEntry(
                    kind: .improvement,
                    text: "Updates are signed by Chykalophia and verified before they install."
                )
            ]
        ),
        ReleaseNote(
            version: "1.0.2",
            date: "October 2026",
            highlights: [
                ChangeEntry(
                    kind: .fix,
                    text: "Punctual stays running: macOS can no longer quit it in the background, "
                        + "which could send first-run setup back to the start after Google sign-in."
                ),
                ChangeEntry(
                    kind: .improvement,
                    text: "No more extra \"Google account connected\" pop-up during setup."
                )
            ]
        ),
        ReleaseNote(
            version: "1.0.1",
            date: "October 2026",
            highlights: [
                ChangeEntry(
                    kind: .feature,
                    text: "Sign in to Google Calendar directly from Preferences, no setup needed. "
                        + "Access is read-only."
                )
            ]
        ),
        ReleaseNote(
            version: "1.0.0",
            date: "October 2026",
            highlights: [
                ChangeEntry(
                    kind: .feature,
                    text: "Meet Punctual. New name, new icon, and the first release signed and "
                        + "notarized by Apple, so it opens without a warning."
                ),
                ChangeEntry(
                    kind: .feature,
                    text: "Apple and Google Calendar together: connect both and every meeting lands "
                        + "in one list, each shown once."
                ),
                ChangeEntry(
                    kind: .feature,
                    text: "Join from the menu bar: a Join chip appears on the status item when a "
                        + "meeting with a link is coming up."
                ),
                ChangeEntry(
                    kind: .improvement,
                    text: "Choose how soon before a meeting the countdown shows, and bring your own "
                        + "Google credentials if your workplace requires it."
                ),
                ChangeEntry(
                    kind: .improvement,
                    text: "Still built on MeetingBar by Andrii Leitsius and its contributors. Thank you."
                )
            ]
        ),
        ReleaseNote(
            version: "0.1.0",
            date: "July 2026",
            highlights: [
                ChangeEntry(
                    kind: .feature,
                    text: "First release, then named MeetingBarNG: a focused, independent fork of MeetingBar, "
                        + "rebuilt for the road ahead. It is called Punctual now."
                ),
                ChangeEntry(
                    kind: .feature,
                    text: "Composable menu bar: assemble your status-bar item from tokens — "
                        + "app icon, meeting title, live countdown, and date."
                ),
                ChangeEntry(
                    kind: .improvement,
                    text: "Calendars come straight from macOS. Every account already in the "
                        + "Calendar app — Google, iCloud, and Exchange — works with no extra sign-in."
                ),
                ChangeEntry(
                    kind: .improvement,
                    text: "The menu now starts at \"now\": meetings that already ended drop off, "
                        + "so today's next event always leads the list."
                ),
                ChangeEntry(
                    kind: .improvement,
                    text: "New installs default to a 12-hour clock. Existing setups keep whichever "
                        + "time format they were already using."
                ),
                ChangeEntry(
                    kind: .fix,
                    text: "Calendar and provider hiccups now fail gracefully with a clear status "
                        + "message instead of an empty menu."
                )
            ]
        )
    ]

    /// Releases strictly newer than the last-acknowledged version. These surface
    /// as the primary "What's New" cards. Keeps the strictly-greater semantics of
    /// `compareVersions` used elsewhere for changelog gating.
    static func releases(newerThan lastRevised: String) -> [ReleaseNote] {
        all.filter { compareVersions($0.version, lastRevised) }
    }

    /// Releases the user has already seen (version <= lastRevised). Shown, when
    /// non-empty, under a collapsed "Earlier releases" disclosure.
    static func releases(upToAndIncluding lastRevised: String) -> [ReleaseNote] {
        all.filter { !compareVersions($0.version, lastRevised) }
    }
}
