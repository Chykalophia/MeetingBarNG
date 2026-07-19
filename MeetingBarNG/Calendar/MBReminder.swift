//
//  MBReminder.swift
//  MeetingBarNG
//
//  Host value type for an Apple Reminder shown in the menu's Today section (Dot
//  parity). Mirrors the MBEvent/MBCalendar value-type pattern: a flat, Sendable
//  snapshot of an `EKReminder` so the rest of the app never touches EventKit
//  types directly. The pure selection/snooze math lives in
//  `Calendar/ReminderSelection.swift` (compiled into MeetingBarLogic); this type
//  is app-target only because it carries an `NSColor`.
//
//  Created for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import AppKit

public struct MBReminder: Identifiable, Hashable, Sendable {
    /// EventKit `calendarItemIdentifier`. Stable enough to re-fetch the reminder
    /// for the check-off / snooze write paths.
    public let id: String
    public let title: String
    public let notes: String?
    public let dueDate: Date?
    /// Whether the reminder's due date components include a time-of-day. When
    /// false the reminder is due "sometime today" and no clock time is shown.
    public let hasTime: Bool
    /// EventKit priority: 0 = none, 1 = high … 9 = low.
    public let priority: Int
    public let isCompleted: Bool
    public let listTitle: String
    public let listColor: NSColor
    /// Pre-computed by the store: the reminder's due date is before the start of
    /// today. Kept on the value type so renderers don't recompute it.
    public let isOverdue: Bool

    public init(
        id: String,
        title: String,
        notes: String?,
        dueDate: Date?,
        hasTime: Bool,
        priority: Int,
        isCompleted: Bool,
        listTitle: String,
        listColor: NSColor,
        isOverdue: Bool
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.hasTime = hasTime
        self.priority = priority
        self.isCompleted = isCompleted
        self.listTitle = listTitle
        self.listColor = listColor
        self.isOverdue = isOverdue
    }
}
