//
//  EventKitEventWriter.swift
//  MeetingBarNG
//
//  EventKit WRITE surface for calendar events (Dot parity: in-app create / edit /
//  delete). Targets `EKEventStore.shared` — the app's static, full-access
//  calendar store — so no new permission or entitlement is needed. Mirrors
//  `RemindersStore`'s Sendable-wrapper + os.Logger error-handling shape.
//
//  Turns a validated, host-free `EventDraft` into an `EKEvent`
//  (`EKEvent(eventStore:)`), sets the standard fields, and
//  `save(_:span:commit:)`s. Edit re-fetches the item by identifier, mutates, and
//  saves; delete re-fetches and `remove`s. Recurring edits/deletes use the
//  `.thisEvent` span for v1 (a single occurrence — series editing is future work).
//
//  Created for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import EventKit
import Foundation

enum EventKitWriteError: LocalizedError {
    case calendarNotFound
    case eventNotFound

    var errorDescription: String? {
        switch self {
        case .calendarNotFound:
            return "The selected calendar is no longer available"
        case .eventNotFound:
            return "The event could not be found in the calendar store"
        }
    }
}

/// Stateless writer over `EKEventStore.shared`. `async` methods are non-isolated,
/// so the EventKit `save`/`remove` work runs off the main actor; the mutated
/// `EKEvent` never crosses a suspension point (it is created/fetched and saved
/// within one method body), which keeps it clear of the Sendable boundary.
struct EventKitEventWriter: Sendable {
    /// Shared instance so the editor's create/update/delete handlers all target
    /// the same static store. Mirrors `EKEventStore.shared` / `RemindersStore.shared`.
    static let shared = EventKitEventWriter()

    /// Calendars the user can actually write to, mapped to `MBCalendar` for the
    /// editor's calendar picker (title + color + id). `MBCalendar` carries no
    /// writable flag, so it is filtered here from the `EKCalendar`'s
    /// `allowsContentModifications`. Cheap enough to read synchronously when the
    /// editor opens.
    @MainActor
    func writableCalendars() -> [MBCalendar] {
        EKEventStore.shared.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map { calendar in
                MBCalendar(
                    title: calendar.title,
                    id: calendar.calendarIdentifier,
                    source: calendar.source.title,
                    email: getGmailAccount(calendar.source.description),
                    color: calendar.color
                )
            }
    }

    /// Creates a new event from `draft` and returns its EventKit identifier.
    func create(draft: EventDraft) async throws -> String {
        let store = EKEventStore.shared
        guard let calendarID = draft.calendarID,
              let calendar = store.calendar(withIdentifier: calendarID) else {
            MeetingBarLogger.calendar.error("Event create failed: calendar not found")
            throw EventKitWriteError.calendarNotFound
        }

        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        Self.apply(draft, to: event)

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            MeetingBarLogger.calendar.error(
                "Event create save failed: \(String(describing: error), privacy: .private)"
            )
            throw error
        }
        return event.eventIdentifier
    }

    /// Re-fetches the event by identifier, applies `draft`, and saves. The
    /// identifier is the raw `calendarItemIdentifier` carried on `MBEvent`
    /// (`scriptIdentifier`), so both lookup APIs are tried.
    func update(id: String, draft: EventDraft) async throws {
        let store = EKEventStore.shared
        guard let event = Self.lookupEvent(id: id, in: store) else {
            MeetingBarLogger.calendar.error(
                "Event update failed: event not found for \(id, privacy: .private)"
            )
            throw EventKitWriteError.eventNotFound
        }

        if let calendarID = draft.calendarID,
           let calendar = store.calendar(withIdentifier: calendarID) {
            event.calendar = calendar
        }
        Self.apply(draft, to: event)

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            MeetingBarLogger.calendar.error(
                "Event update save failed for \(id, privacy: .private): \(String(describing: error), privacy: .private)"
            )
            throw error
        }
    }

    /// Re-fetches the event by identifier and removes it (`.thisEvent` span).
    func delete(id: String) async throws {
        let store = EKEventStore.shared
        guard let event = Self.lookupEvent(id: id, in: store) else {
            MeetingBarLogger.calendar.error(
                "Event delete failed: event not found for \(id, privacy: .private)"
            )
            throw EventKitWriteError.eventNotFound
        }

        do {
            try store.remove(event, span: .thisEvent, commit: true)
        } catch {
            MeetingBarLogger.calendar.error(
                "Event delete failed for \(id, privacy: .private): \(String(describing: error), privacy: .private)"
            )
            throw error
        }
    }

    // MARK: - Helpers

    /// `MBEvent` stores the raw `calendarItemIdentifier` as `scriptIdentifier`;
    /// try the event-identifier lookup first, then fall back to the calendar-item
    /// identifier so either flavor resolves.
    private static func lookupEvent(id: String, in store: EKEventStore) -> EKEvent? {
        if let event = store.event(withIdentifier: id) {
            return event
        }
        return store.calendarItem(withIdentifier: id) as? EKEvent
    }

    private static func apply(_ draft: EventDraft, to event: EKEvent) {
        event.title = draft.title
        event.isAllDay = draft.isAllDay
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.location = draft.location.isEmpty ? nil : draft.location
        event.notes = draft.notes.isEmpty ? nil : draft.notes

        let trimmedURL = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
        event.url = trimmedURL.isEmpty ? nil : URL(string: trimmedURL)
    }
}
