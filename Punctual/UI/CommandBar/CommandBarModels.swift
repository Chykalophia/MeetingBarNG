//
//  CommandBarModels.swift
//  MeetingBarNG
//
//  Hostless value types for the Command Bar (Dot parity). Foundation-only, so
//  they compile into the MeetingBarLogic module and are unit-tested without a
//  host. Localized strings are supplied by the app (CommandBarActionDescriptor
//  carries already-localized text), keeping `.loco()` out of the pure module.
//  No AI/LLM, no natural-language event creation — text matching only.
//

import Foundation

/// Flat projection of an event for the Command Bar. `sourceIndex` maps a result
/// row back to the caller's `[MBEvent]`. `subtitle` is preformatted app-side so
/// locale/time formatting stays out of the pure module.
struct CommandBarEventInput: Equatable {
    let sourceIndex: Int
    let id: String
    let title: String
    let subtitle: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let hasMeetingLink: Bool
    let location: String?
    let notes: String?
    /// Flattened attendee/organizer names + emails ("people"), for search.
    let attendees: [String]
}

/// The fixed quick actions the Command Bar can run. Wired to existing entry
/// points app-side (createMeeting / join / openPreferences / clipboard).
enum CommandBarAction: String, Equatable, CaseIterable {
    case joinNext
    case createMeeting
    case openPreferences
    case copyAgenda
    case refreshCalendars
}

/// An action plus its localized presentation and match synonyms. Built app-side
/// so the pure matcher never localizes.
struct CommandBarActionDescriptor: Equatable {
    let action: CommandBarAction
    let title: String
    let subtitle: String?
    /// Already-localized terms the query is matched against (e.g. "join", "next").
    let searchableText: [String]
    /// Shown first (before events) in the empty-query default ordering.
    let isPriority: Bool
}

/// What a row resolves to when the user runs it.
enum CommandBarResult: Equatable {
    case action(CommandBarAction)
    /// The event's id — the app resolves it back to an MBEvent.
    case event(String)
}

/// A ranked, display-ready row. Presentation-only fields (title/subtitle) are
/// already localized/preformatted; `result` is what to execute.
struct CommandBarResultRow: Equatable {
    let result: CommandBarResult
    let title: String
    let subtitle: String?
    let score: Double
}
