//
//  RemindersStore.swift
//  MeetingBarNG
//
//  EventKit service for Apple Reminders shown in the menu (Dot parity). Owns its
//  OWN `EKEventStore`, separate from the calendar store (`EKEventStore.shared`),
//  so the reminders permission is requested and held independently and only when
//  the user opts in. Mirrors `EventKitEventStore`'s access-request shape
//  (`requestFullAccessToReminders` on macOS 14+, `requestAccess(to:.reminder)`
//  fallback) and the off-main fetch pattern.
//
//  This is the app's first EventKit WRITE surface: `complete(id:)` and
//  `reschedule(id:to:)` re-fetch the `EKReminder` by identifier, mutate it, and
//  `save(commit:)`.
//
//  Created for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import AppKit
import EventKit
import Foundation

/// Thread-safe (`Sendable`) wrapper around a private `EKEventStore` scoped to
/// reminders. Async methods are non-isolated, so fetch/save run off the main
/// actor on the global executor.
final class RemindersStore: Sendable {
    /// Shared instance so the preferences toggle (permission prompt), the sync,
    /// and the write paths all target the same `EKEventStore`. Mirrors
    /// `EKEventStore.shared` for the calendar side.
    static let shared = RemindersStore()

    private let store = EKEventStore()

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    /// Whether the app currently has read/write access to reminders.
    var isAccessGranted: Bool {
        Self.isGranted(authorizationStatus)
    }

    static func isGranted(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    /// Requests reminders access. This is the ONLY entry point that triggers the
    /// system permission prompt — wired to the "Show reminders in menu" toggle.
    @discardableResult
    func requestAccess() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let handler: @Sendable (Bool, (any Error)?) -> Void = { granted, error in
                if let error {
                    MeetingBarLogger.calendar.error(
                        "Reminders access request failed: \(String(describing: error), privacy: .private)"
                    )
                }
                continuation.resume(returning: granted)
            }

            if #available(macOS 14, *) {
                store.requestFullAccessToReminders(completion: handler)
            } else {
                store.requestAccess(to: .reminder, completion: handler)
            }
        }
    }

    /// Incomplete reminders due today or earlier. Returns `[]` (and logs nothing)
    /// when access has not been granted, so callers never need to pre-check.
    func fetchDueToday() async -> [MBReminder] {
        guard isAccessGranted else { return [] }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }

        // predicateForIncompleteReminders is inherently incomplete-only, so the
        // hostless ReminderSelection filter only has to apply the overdue policy.
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: endOfDay,
            calendars: nil
        )

        // fetchReminders(matching:) is completion-based; bridge to async. Map to
        // the Sendable MBReminder inside the completion so no EKReminder crosses
        // the continuation boundary.
        return await withCheckedContinuation { (continuation: CheckedContinuation<[MBReminder], Never>) in
            _ = store.fetchReminders(matching: predicate) { reminders in
                let mapped = (reminders ?? []).map { makeReminder(from: $0, now: now, calendar: calendar) }
                continuation.resume(returning: mapped)
            }
        }
    }

    /// Marks the reminder complete and commits. Re-fetches by identifier because
    /// the value type handed to the UI does not retain the `EKReminder`.
    func complete(id: String) async {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            MeetingBarLogger.calendar.error(
                "Reminder to complete not found: \(id, privacy: .private)"
            )
            return
        }
        reminder.isCompleted = true
        save(reminder, action: "complete", id: id)
    }

    /// Reschedules the reminder's due date (Dot-style snooze — reflected back
    /// into Apple Reminders) and adds an alarm so it re-notifies at the new time.
    func reschedule(id: String, to date: Date) async {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            MeetingBarLogger.calendar.error(
                "Reminder to reschedule not found: \(id, privacy: .private)"
            )
            return
        }
        let calendar = Calendar.current
        reminder.dueDateComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        reminder.addAlarm(EKAlarm(absoluteDate: date))
        save(reminder, action: "reschedule", id: id)
    }

    private func save(_ reminder: EKReminder, action: String, id: String) {
        do {
            try store.save(reminder, commit: true)
        } catch {
            MeetingBarLogger.calendar.error(
                "Reminder \(action, privacy: .public) save failed for \(id, privacy: .private): \(String(describing: error), privacy: .private)"
            )
        }
    }
}

/// Maps an `EKReminder` to the flat, Sendable `MBReminder` value type. Free
/// function so it can run inside the (non-Sendable) fetch completion closure
/// without capturing the store.
private func makeReminder(from reminder: EKReminder, now: Date, calendar: Calendar) -> MBReminder {
    let components = reminder.dueDateComponents
    let dueDate = components.flatMap { calendar.date(from: $0) }
    let hasTime = components?.hour != nil
    let startOfToday = calendar.startOfDay(for: now)
    let isOverdue = dueDate.map { $0 < startOfToday } ?? false

    return MBReminder(
        id: reminder.calendarItemIdentifier,
        title: reminder.title ?? "",
        notes: reminder.notes,
        dueDate: dueDate,
        hasTime: hasTime,
        priority: reminder.priority,
        isCompleted: reminder.isCompleted,
        listTitle: reminder.calendar?.title ?? "",
        listColor: reminder.calendar?.color ?? NSColor.systemGray,
        isOverdue: isOverdue
    )
}
