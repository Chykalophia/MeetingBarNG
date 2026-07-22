//
//  FilterPresets.swift
//  MeetingBarNG
//
//  Hostless resolution for the Filters pane (Preferences UX overhaul, Phase 2).
//
//  Three pieces of pure logic that the SwiftUI pane must not own:
//
//    1. `FilterPreset` — the "Everything / Meetings only / Only what I accepted"
//       chips. A chip WRITES a set of stored values; the selected chip is
//       DERIVED from the stored values, so `Custom` can never be a mode you get
//       stuck in (or lose on window close).
//    2. `EndedMeetingsVisibility` — the merge of `pastEventsAppereance` and
//       `hideFinishedEventsInMenu` into one Show / Dim / Hide row. The two keys
//       overlapped, could contradict, lived on two different tabs, and nothing
//       stated precedence.
//    3. `FilterVocabularyMigration` — "show as underlined" is deleted as an
//       option, so anyone holding it is moved to Dim once, deliberately.
//
//  Values are plain raw strings, not the app's `Defaults`-serializable enums, so
//  this file compiles into MeetingBarLogic and is unit-tested without a host.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Foundation

/// The stored key names the Filters presets write. Raw strings so the hostless
/// module never imports `Defaults`.
enum FilterDefaultsKey {
    static let allDay = "allDayEvents"
    static let noLink = "nonAllDayEvents"
    static let solo = "personalEventsAppereance"
    static let pending = "showPendingEvents"
    static let tentative = "showTentativeEvents"
    static let declined = "declinedEventsAppereance"
    static let ended = "pastEventsAppereance"
    static let hideFinished = "hideFinishedEventsInMenu"
}

/// One-click starting points for the seven per-kind filter rows.
///
/// `custom` is a *label*, not a mode: it is what the pane shows when the stored
/// values match no named preset. Nothing is stored to say "I am custom", so a
/// hand-tuned set survives quitting Preferences.
enum FilterPreset: String, CaseIterable, Sendable {
    case everything
    case meetingsOnly
    case acceptedOnly
    case custom

    var titleKey: String {
        switch self {
        case .everything: "preferences_filters_preset_everything"
        case .meetingsOnly: "preferences_filters_preset_meetings_only"
        case .acceptedOnly: "preferences_filters_preset_accepted_only"
        case .custom: "preferences_filters_preset_custom"
        }
    }

    /// Stored key name → raw value. Empty for `.custom`, which writes nothing.
    var values: [String: String] {
        switch self {
        case .everything:
            [
                FilterDefaultsKey.allDay: "show",
                FilterDefaultsKey.noLink: "show",
                FilterDefaultsKey.solo: "show_active",
                FilterDefaultsKey.pending: "show",
                FilterDefaultsKey.tentative: "show",
                // `strikethrough` is this key's only non-dim, non-hidden value —
                // the enum has no plain `show` case (see FiltersTab).
                FilterDefaultsKey.declined: "strikethrough",
                FilterDefaultsKey.ended: "show_inactive",
                FilterDefaultsKey.hideFinished: "false"
            ]
        case .meetingsOnly:
            [
                FilterDefaultsKey.allDay: "hide",
                FilterDefaultsKey.noLink: "hide_without_meeting_link",
                FilterDefaultsKey.solo: "hide",
                FilterDefaultsKey.pending: "show",
                FilterDefaultsKey.tentative: "show",
                FilterDefaultsKey.declined: "hide",
                FilterDefaultsKey.ended: "hide",
                FilterDefaultsKey.hideFinished: "true"
            ]
        case .acceptedOnly:
            [
                FilterDefaultsKey.allDay: "hide",
                FilterDefaultsKey.noLink: "hide_without_meeting_link",
                FilterDefaultsKey.solo: "hide",
                FilterDefaultsKey.pending: "hide",
                FilterDefaultsKey.tentative: "hide",
                FilterDefaultsKey.declined: "hide",
                FilterDefaultsKey.ended: "hide",
                FilterDefaultsKey.hideFinished: "true"
            ]
        case .custom:
            [:]
        }
    }

    /// The named preset whose values exactly match `values`, else `.custom`.
    static func detect(_ values: [String: String]) -> FilterPreset {
        allCases.first { $0 != .custom && $0.values == values } ?? .custom
    }
}

/// The single Show / Dim / Hide vocabulary the Filters rows speak.
enum FilterVisibility: String, CaseIterable, Sendable {
    case show
    case dim
    case hide

    var titleKey: String {
        switch self {
        case .show: "preferences_filters_value_show"
        case .dim: "preferences_filters_value_dim"
        case .hide: "preferences_filters_value_hide"
        }
    }
}

/// "Meetings that have ended" is one row over two stored keys.
///
/// Precedence, stated once and here only: **hide wins**. Either key asking to
/// hide hides, because a user who set either one expects finished meetings gone.
enum EndedMeetingsVisibility {
    /// Read the merged row from both stored values.
    static func resolve(pastRawValue: String, hideFinished: Bool) -> FilterVisibility {
        if hideFinished || pastRawValue == "hide" { return .hide }
        return pastRawValue == "show_inactive" ? .dim : .show
    }

    /// Write the merged row back to both stored values, so they can never
    /// contradict each other again.
    static func storedValues(for visibility: FilterVisibility) -> (past: String, hideFinished: Bool) {
        switch visibility {
        case .show: ("show_active", false)
        case .dim: ("show_inactive", false)
        case .hide: ("hide", true)
        }
    }
}

/// "show as underlined" is deleted as an option value: three vocabularies
/// (show/dim/underline/strikethrough) collapse into one (Show/Dim/Hide).
///
/// The stored case still exists and the classic menu still renders it, so this
/// is a one-shot value migration, not a schema change: anyone holding it lands
/// on Dim — the honest neighbour — instead of meeting a picker with nothing
/// selected.
enum FilterVocabularyMigration {
    static let retiredRawValue = "show_underlined"
    static let replacementRawValue = "show_inactive"

    /// The value to store instead, or `nil` when the stored value is fine.
    static func migrated(_ rawValue: String) -> String? {
        rawValue == retiredRawValue ? replacementRawValue : nil
    }
}
