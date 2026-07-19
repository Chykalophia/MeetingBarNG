//
//  EventEditorViewModel.swift
//  MeetingBarNG
//
//  App-target view model for the in-app event editor (Dot parity: create / edit /
//  delete calendar events). Owns the editable fields, projects them into the
//  hostless `EventDraft`, runs `EventDraftValidation` to gate Save, and dispatches
//  create/update/delete through injected handlers (resolved by AppDelegate from
//  the EventKit writer). Delete requires an NSAlert confirmation first. The
//  SwiftUI view stays presentation-only.
//
//  Created for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import AppKit
import Foundation

/// Whether the editor is composing a new event or editing an existing one.
enum EventEditorMode {
    case create
    case edit(MBEvent)
}

/// Closures the editor needs from the app, injected by AppDelegate so the view
/// model stays decoupled from the EventKit writer / CalendarSync / coordinator.
/// `dismiss` is supplied by the WindowCoordinator (it owns the window).
struct EventEditorHandlers {
    var create: @MainActor (_ draft: EventDraft) async throws -> Void
    var update: @MainActor (_ id: String, _ draft: EventDraft) async throws -> Void
    var delete: @MainActor (_ id: String) async throws -> Void
    var writableCalendars: @MainActor () -> [MBCalendar]
    var dismiss: @MainActor () -> Void
}

@MainActor
final class EventEditorViewModel: ObservableObject {
    @Published var title: String
    @Published var isAllDay: Bool
    @Published var startDate: Date
    @Published var endDate: Date
    @Published var selectedCalendarID: String?
    @Published var location: String
    @Published var notes: String
    @Published var url: String

    /// A write failure to surface inline (validation issues are shown separately).
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSaving = false

    let writableCalendars: [MBCalendar]
    let isEditing: Bool

    private let handlers: EventEditorHandlers
    /// Raw EventKit identifier (`MBEvent.scriptIdentifier`) for edit/delete.
    private let editingID: String?

    init(mode: EventEditorMode, handlers: EventEditorHandlers) {
        self.handlers = handlers
        let calendars = handlers.writableCalendars()
        self.writableCalendars = calendars

        switch mode {
        case .create:
            isEditing = false
            editingID = nil
            title = ""
            isAllDay = false
            let start = EventEditorViewModel.defaultStartDate()
            startDate = start
            endDate = start.addingTimeInterval(3600)
            selectedCalendarID = calendars.first?.id
            location = ""
            notes = ""
            url = ""
        case let .edit(event):
            isEditing = true
            editingID = event.scriptIdentifier
            title = event.title
            isAllDay = event.isAllDay
            startDate = event.startDate
            endDate = event.endDate
            // Prefer the event's own calendar; fall back to the first writable one
            // if the event lives in a read-only calendar.
            let eventCalendarID = event.calendar.id
            selectedCalendarID = calendars.contains { $0.id == eventCalendarID }
                ? eventCalendarID
                : calendars.first?.id
            location = event.location ?? ""
            notes = event.notes ?? ""
            url = event.url?.absoluteString ?? ""
        }
    }

    // MARK: - Derived state

    var draft: EventDraft {
        EventDraft(
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            calendarID: selectedCalendarID,
            location: location,
            notes: notes,
            url: url
        )
    }

    var validationErrors: [EventDraftError] {
        EventDraftValidation.validate(draft)
    }

    var canSave: Bool {
        !isSaving && validationErrors.isEmpty
    }

    /// The first validation problem, localized, for the inline hint under the form.
    var firstValidationMessage: String? {
        validationErrors.first.map(Self.message(for:))
    }

    static func message(for error: EventDraftError) -> String {
        switch error {
        case .emptyTitle:
            return "event_editor_validation_empty_title".loco()
        case .endBeforeStart:
            return "event_editor_validation_end_before_start".loco()
        case .missingCalendar:
            return "event_editor_validation_missing_calendar".loco()
        }
    }

    // MARK: - Actions

    func save() {
        guard canSave else { return }
        errorMessage = nil
        isSaving = true
        let draft = self.draft
        let mode: SaveMode = editingID.map { .update($0) } ?? .create

        Task {
            do {
                switch mode {
                case .create:
                    try await handlers.create(draft)
                case let .update(id):
                    try await handlers.update(id, draft)
                }
                handlers.dismiss()
            } catch {
                MeetingBarLogger.calendar.error(
                    "Event editor save failed: \(String(describing: error), privacy: .private)"
                )
                errorMessage = "event_editor_save_failed".loco()
                isSaving = false
            }
        }
    }

    /// Confirms via a destructive NSAlert BEFORE deleting; only proceeds on the
    /// explicit Delete button.
    func confirmAndDelete() {
        guard let editingID else { return }

        let alert = NSAlert()
        alert.messageText = "event_editor_delete_confirm_title".loco()
        alert.informativeText = "event_editor_delete_confirm_message".loco(title)
        alert.alertStyle = .warning
        let deleteButton = alert.addButton(withTitle: "event_editor_delete".loco())
        deleteButton.hasDestructiveAction = true
        alert.addButton(withTitle: "event_editor_cancel".loco())

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        errorMessage = nil
        isSaving = true
        Task {
            do {
                try await handlers.delete(editingID)
                handlers.dismiss()
            } catch {
                MeetingBarLogger.calendar.error(
                    "Event editor delete failed: \(String(describing: error), privacy: .private)"
                )
                errorMessage = "event_editor_delete_failed".loco()
                isSaving = false
            }
        }
    }

    func cancel() {
        handlers.dismiss()
    }

    // MARK: - Private

    private enum SaveMode {
        case create
        case update(String)
    }

    /// Next top-of-the-hour from now, so a new event defaults to a sensible slot.
    private static func defaultStartDate() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let nextHour = calendar.nextDate(
            after: now,
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .nextTime
        )
        return nextHour ?? now
    }
}
