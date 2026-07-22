//
//  DropdownComposition.swift
//  MeetingBarNG
//
//  Hostless model for the composable menu dropdown (MeetingBarNG). Pure value
//  types + resolution math only — no AppKit/Defaults/EventKit. Mirrors the
//  `MenuBarComposition` / `MenuBarTokenKind` convention used for the menu-bar
//  title composer: the raw string list is the source of truth, and unknown /
//  renamed entries degrade gracefully so a downgrade or a hand-edited Defaults
//  value can never crash or drop the dropdown.
//

import Foundation

/// A reorderable, toggleable section of the menu dropdown. The Preferences
/// footer is intentionally NOT a module — it stays pinned as the last block so
/// the user can never lock themselves out of Settings/Quit.
enum DropdownModule: String, CaseIterable, Codable, Hashable {
    /// The day-summary greeting header at the very top of the dropdown.
    case greeting
    /// The day-relative timeline bar.
    case timeline
    /// The next/current meeting control card (or its empty state).
    case meeting
    /// Today's (and optionally tomorrow's) date sections plus reminders.
    case agenda
    /// Join / create / quick-actions rows.
    case join
    /// The saved bookmarks section.
    case bookmarks
}

/// An ordered list of dropdown modules. `standard` is the canonical order that
/// reproduces the classic dropdown layout, so a fresh install (or an empty
/// stored order) renders exactly as before.
struct DropdownComposition: Equatable {
    var modules: [DropdownModule]

    /// THIS EXACT ORDER reproduces the current dropdown layout
    /// (greeting → timeline → meeting → agenda → join → bookmarks).
    static let standard = DropdownComposition(
        modules: [.greeting, .timeline, .meeting, .agenda, .join, .bookmarks]
    )
}

/// Pure, deterministic resolution of the stored order + per-module enabled set
/// into the concrete list of modules to render, in order.
enum DropdownCompositionPolicy {
    /// Resolves the visible, ordered modules from a stored raw order and the set
    /// of enabled module raw values.
    ///
    /// 1. Parse `rawOrder` into `DropdownModule`, dropping unknowns and de-duping
    ///    (first occurrence wins).
    /// 2. Append any module absent from `rawOrder`, in `standard` order — so a
    ///    module added in a future build surfaces even for users whose stored
    ///    order predates it.
    /// 3. Keep only modules whose `rawValue` is in `enabled`.
    static func resolve(order rawOrder: [String], enabled: Set<String>) -> [DropdownModule] {
        var seen = Set<DropdownModule>()
        var ordered: [DropdownModule] = []

        for raw in rawOrder {
            guard let module = DropdownModule(rawValue: raw) else { continue }
            if seen.insert(module).inserted {
                ordered.append(module)
            }
        }

        for module in DropdownComposition.standard.modules where seen.insert(module).inserted {
            ordered.append(module)
        }

        return ordered.filter { enabled.contains($0.rawValue) }
    }

    // swiftlint:disable function_parameter_count
    /// The raw values of the dropdown modules whose per-module toggle is on — the
    /// `enabled` set fed to `resolve(order:enabled:)`. Shared by the status-bar
    /// controller (which builds the real NSMenu) and the Display-tab live preview
    /// so the preview can never drift from what the menu actually renders.
    /// `greeting`/`timeline` reuse the existing preferences; the rest use the
    /// MeetingBarNG per-module toggles. One boolean per module keeps call sites
    /// self-documenting.
    static func enabledRawValues(
        greeting: Bool,
        timeline: Bool,
        meeting: Bool,
        agenda: Bool,
        join: Bool,
        bookmarks: Bool
    ) -> Set<String> {
        // swiftlint:enable function_parameter_count
        var enabled = Set<String>()
        if greeting { enabled.insert(DropdownModule.greeting.rawValue) }
        if timeline { enabled.insert(DropdownModule.timeline.rawValue) }
        if meeting { enabled.insert(DropdownModule.meeting.rawValue) }
        if agenda { enabled.insert(DropdownModule.agenda.rawValue) }
        if join { enabled.insert(DropdownModule.join.rawValue) }
        if bookmarks { enabled.insert(DropdownModule.bookmarks.rawValue) }
        return enabled
    }
}
