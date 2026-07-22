//
//  ReminderSelection+MeetingBar.swift
//  MeetingBarNG
//
//  App-target adapter bridging the host `MBReminder` value type to the hostless
//  `ReminderSelectionItem` / `ReminderSelection` logic (Calendar/ReminderSelection.swift).
//  Mirrors `EventSelection+MeetingBar.swift`: the pure module stays free of
//  AppKit/EventKit while the app maps its richer value type onto it.
//
//  Created for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Foundation

extension ReminderSelectionItem {
    init(reminder: MBReminder, sourceIndex: Int) {
        self.init(
            sourceIndex: sourceIndex,
            id: reminder.id,
            dueDate: reminder.dueDate,
            hasTime: reminder.hasTime,
            priority: reminder.priority,
            isCompleted: reminder.isCompleted
        )
    }
}

extension Array where Element == MBReminder {
    /// Incomplete reminders due today (optionally including overdue), sorted by
    /// the hostless `ReminderSelection.dueToday` policy. Maps each selected item
    /// back to its original `MBReminder` via `sourceIndex`.
    func dueToday(
        now: Date = Date(),
        includeOverdue: Bool,
        calendar: Calendar = .current
    ) -> [MBReminder] {
        let items = enumerated().map { index, reminder in
            ReminderSelectionItem(reminder: reminder, sourceIndex: index)
        }
        return ReminderSelection.dueToday(
            from: items,
            now: now,
            calendar: calendar,
            includeOverdue: includeOverdue
        )
        .map { self[$0.sourceIndex] }
    }
}
