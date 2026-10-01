//
//  EventActionProminence.swift
//  MeetingBarNG
//
//  Whether an event's action control (Join today; whatever else earns the slot
//  later) should render as a call to action or as a recessed, available-but-not-
//  urgent control.
//
//  Hostless and pure so the rule is unit-testable and, more importantly, so every
//  surface that draws the control — the dropdown's event rows, its meeting card,
//  and the menu bar's progress indicator — decides it the same way. Duplicating
//  four lines of date math across them is exactly the kind of thing that drifts
//  once a preference is attached to it.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Foundation

enum EventActionProminence {
    /// `true` when the meeting is currently running, or starts within
    /// `leadMinutes`.
    ///
    /// Styling only — callers keep the control clickable either way, because
    /// joining early is perfectly legitimate. What this exists to prevent is a
    /// meeting six hours out wearing the same bright treatment as one about to
    /// begin, which reads as "click me now" when nothing needs clicking.
    ///
    /// A meeting that has already ended is NOT imminent: `now < end` is checked
    /// rather than assumed, so a stale row left open in the panel recedes on its
    /// own rather than staying lit indefinitely.
    ///
    /// - Parameter leadMinutes: negatives are clamped to zero, so a corrupt or
    ///   hand-edited preference degrades to "only while running" instead of
    ///   inverting the comparison and lighting up everything.
    static func isImminent(
        start: Date,
        end: Date,
        now: Date,
        leadMinutes: Int
    ) -> Bool {
        if start <= now { return now < end }
        return start.timeIntervalSince(now) <= Double(max(0, leadMinutes)) * 60
    }
}
