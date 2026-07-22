//
//  ReminderSelection.swift
//  MeetingBarNG
//
//  Hostless selection + snooze logic for Apple Reminders in the menu (Dot
//  parity). Pure value types + math only — no AppKit/EventKit — so it compiles
//  into the MeetingBarLogic module and is unit-tested without a host. Mirrors
//  the EventSelection value-type + pure-function pattern.
//

import Foundation

/// Flat mirror of a reminder for hostless filtering/sorting. `sourceIndex` maps
/// a result back to the caller's `[MBReminder]`.
struct ReminderSelectionItem: Equatable {
    let sourceIndex: Int
    let id: String
    let dueDate: Date?
    let hasTime: Bool
    /// EventKit priority: 0 = none, 1 = high … 9 = low.
    let priority: Int
    let isCompleted: Bool
}

enum ReminderSelection {
    /// Incomplete reminders due today (optionally including overdue), sorted
    /// overdue-first, then by due date ascending, then priority (high first),
    /// then `sourceIndex` for stability.
    ///
    /// Reminders with no due date are excluded — "due today" requires a due date.
    static func dueToday(
        from reminders: [ReminderSelectionItem],
        now: Date,
        calendar: Calendar,
        includeOverdue: Bool
    ) -> [ReminderSelectionItem] {
        let startOfDay = calendar.startOfDay(for: now)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }

        let filtered = reminders.filter { item in
            guard !item.isCompleted, let due = item.dueDate else { return false }
            guard due < endOfDay else { return false }        // due today or earlier
            if due < startOfDay { return includeOverdue }      // overdue only if requested
            return true
        }

        return filtered.sorted { lhs, rhs in
            let lhsOverdue = (lhs.dueDate ?? .distantFuture) < startOfDay
            let rhsOverdue = (rhs.dueDate ?? .distantFuture) < startOfDay
            if lhsOverdue != rhsOverdue { return lhsOverdue }

            let lhsDue = lhs.dueDate ?? .distantFuture
            let rhsDue = rhs.dueDate ?? .distantFuture
            if lhsDue != rhsDue { return lhsDue < rhsDue }

            if lhs.priority != rhs.priority { return priorityRank(lhs.priority) < priorityRank(rhs.priority) }
            return lhs.sourceIndex < rhs.sourceIndex
        }
    }

    /// Maps EventKit priority (0 = none, 1 high … 9 low) to a sort rank where a
    /// higher priority sorts first and "none" sorts last.
    private static func priorityRank(_ priority: Int) -> Int {
        priority == 0 ? Int.max : priority
    }
}

/// Snooze targets offered on a reminder (reschedules its own due date, Dot-style
/// — reflected back into Apple Reminders, distinct from notification snoozing).
enum ReminderSnoozeOption: String, CaseIterable, Equatable {
    case laterToday
    case thisEvening
    case tomorrow
}

enum ReminderSnoozePolicy {
    /// New due date for a snooze option, handling already-passed target hours:
    /// - `.laterToday`   → now + 1 hour.
    /// - `.thisEvening`  → today at `eveningHour`, or now + 1 hour if already past.
    /// - `.tomorrow`     → tomorrow at `morningHour`.
    static func newDueDate(
        from now: Date,
        option: ReminderSnoozeOption,
        calendar: Calendar,
        eveningHour: Int = 18,
        morningHour: Int = 9
    ) -> Date {
        switch option {
        case .laterToday:
            return now.addingTimeInterval(3600)
        case .thisEvening:
            let startOfDay = calendar.startOfDay(for: now)
            let evening = calendar.date(bySettingHour: eveningHour, minute: 0, second: 0, of: startOfDay)
                ?? now.addingTimeInterval(3600)
            return evening > now ? evening : now.addingTimeInterval(3600)
        case .tomorrow:
            let startOfDay = calendar.startOfDay(for: now)
            let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now
            return calendar.date(bySettingHour: morningHour, minute: 0, second: 0, of: tomorrowStart)
                ?? tomorrowStart
        }
    }
}
