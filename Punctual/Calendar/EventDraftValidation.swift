//
//  EventDraftValidation.swift
//  MeetingBarNG
//
//  Hostless validation for the in-app event editor (Dot parity: create / edit
//  calendar events). Pure value types + rules only — no AppKit/EventKit/Defaults
//  and no localization — so it compiles into the MeetingBarLogic module and is
//  unit-tested without a host. The UI layer maps `EventDraftError` cases to
//  localized messages; the write service turns a validated `EventDraft` into an
//  `EKEvent`. Mirrors the EventFiltering / ReminderSelection pure-logic pattern.
//
//  Created for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Foundation

/// Flat, host-free description of an event the user is composing in the editor.
/// `calendarID` is optional so the "no calendar chosen" state is representable
/// and caught by validation rather than crashing the write path.
struct EventDraft: Equatable, Sendable {
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var calendarID: String?
    var location: String
    var notes: String
    var url: String

    init(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarID: String?,
        location: String = "",
        notes: String = "",
        url: String = ""
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.location = location
        self.notes = notes
        self.url = url
    }
}

/// A single reason a draft can't be saved. The UI renders the first one inline
/// and disables Save while any exist.
enum EventDraftError: Equatable, Sendable {
    case emptyTitle
    case endBeforeStart
    case missingCalendar
}

enum EventDraftValidation {
    /// Returns every problem with `draft`, in a stable order (title, then time,
    /// then calendar). An empty result means the draft is savable.
    ///
    /// - A timed event requires `endDate` strictly after `startDate`.
    /// - An all-day event may have `endDate == startDate` (a single-day event),
    ///   so only an end that falls *before* the start is rejected.
    static func validate(_ draft: EventDraft) -> [EventDraftError] {
        var errors: [EventDraftError] = []

        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyTitle)
        }

        if draft.isAllDay {
            if draft.endDate < draft.startDate {
                errors.append(.endBeforeStart)
            }
        } else if draft.endDate <= draft.startDate {
            errors.append(.endBeforeStart)
        }

        if draft.calendarID?.isEmpty ?? true {
            errors.append(.missingCalendar)
        }

        return errors
    }
}
