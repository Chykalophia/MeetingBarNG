//
//  NotificationPlanningPolicy.swift
//  MeetingBar
//

import Foundation

/// Categories of per-event reminders MeetingBar can produce.
enum NotificationKind: String, CaseIterable, Equatable, Sendable {
    case eventStart  // system notification before the event begins
    case eventEnd  // system notification before the event ends
    case fullscreen  // fullscreen overlay window
    case autoJoin  // automatically open the meeting URL
    case scriptOnStart  // run the user-configured AppleScript
}

/// A single concrete reminder the scheduler should reconcile to the OS.
///
/// `identity` is the stable key the scheduler uses to deduplicate against
/// already-pending requests. Two `PlannedNotification` values with the same
/// `identity` are considered the same scheduled action even if `fireDate`
/// drifts (e.g. across calendar refreshes).
struct PlannedNotification: Equatable, Sendable {
    let eventID: String
    let kind: NotificationKind
    let fireDate: Date
    let identity: String
}

struct NotificationPlanningEvent: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case active
        case canceled
    }

    enum ParticipationStatus: Equatable, Sendable {
        case active
        case declined
    }

    let id: String
    let startDate: Date
    let endDate: Date
    let status: Status
    let participationStatus: ParticipationStatus
    let isAllDay: Bool
    let hasMeetingLink: Bool
    /// Per-event override of the start reminder. `nil` follows the global setting.
    ///
    /// A `var` with a default so every existing construction site keeps compiling
    /// and keeps its current behaviour — an override is opt-in per meeting.
    var startReminderOverride: StartReminderOverride?
}

/// A per-event override of the event-start reminder.
///
/// Three states in total, counting the absence of one: no override follows the
/// global setting, `.suppressed` silences this meeting alone, and `.offset`
/// gives it its own lead time. "Inherit" has to be distinguishable from "off",
/// or turning the global reminder on later would silently un-silence a meeting
/// the user had deliberately quieted.
enum StartReminderOverride: Equatable, Sendable {
    /// No start reminder for this event, even when the global setting is on.
    case suppressed
    /// Seconds before the start. `0` means at the start.
    case offset(TimeInterval)
}

struct NotificationPlanningSettings: Equatable, Sendable {
    struct Action: Equatable, Sendable {
        let enabled: Bool
        /// Seconds before the reference moment (start or end). 0 = at the moment.
        let offset: TimeInterval

        static let disabled = Action(enabled: false, offset: 0)
    }

    let eventStart: Action
    let eventEnd: Action
    let fullscreen: Action
    let autoJoin: Action
    let scriptOnStart: Action
    let dismissedEventIDs: Set<String>
    let fullscreenNotificationsForEventsWithoutMeetingLink: Bool

    /// Whether to hide the event title in notifications (replaced with a generic label).
    let hideMeetingTitle: Bool
    /// Pre-computed body string for the event-start notification.
    let eventStartBody: String
    /// Pre-computed body string for the event-end notification.
    let eventEndBody: String

    init(
        eventStart: Action,
        eventEnd: Action,
        fullscreen: Action,
        autoJoin: Action,
        scriptOnStart: Action,
        dismissedEventIDs: Set<String>,
        fullscreenNotificationsForEventsWithoutMeetingLink: Bool = false,
        hideMeetingTitle: Bool = false,
        eventStartBody: String = "",
        eventEndBody: String = ""
    ) {
        self.eventStart = eventStart
        self.eventEnd = eventEnd
        self.fullscreen = fullscreen
        self.autoJoin = autoJoin
        self.scriptOnStart = scriptOnStart
        self.dismissedEventIDs = dismissedEventIDs
        self.fullscreenNotificationsForEventsWithoutMeetingLink =
            fullscreenNotificationsForEventsWithoutMeetingLink
        self.hideMeetingTitle = hideMeetingTitle
        self.eventStartBody = eventStartBody
        self.eventEndBody = eventEndBody
    }
}

enum NotificationPlanner {
    /// Returns the list of reminders that should be live for the given events
    /// at `now`. Output is sorted ascending by `fireDate`.
    ///
    /// All-day events are deliberately not planned: timed system notifications
    /// at midnight are not useful, and the runtime is responsible for firing
    /// fullscreen / auto-join / script for an all-day event while `now` lies
    /// inside the event range. The runtime layer can read the same `events`
    /// list directly for that case.
    static func plan(
        events: [NotificationPlanningEvent],
        settings: NotificationPlanningSettings,
        now: Date
    ) -> [PlannedNotification] {
        var planned: [PlannedNotification] = []

        for event in events
        where shouldConsider(event: event, dismissed: settings.dismissedEventIDs) {
            appendIfDue(
                .eventStart,
                anchor: event.startDate,
                action: startAction(global: settings.eventStart, override: event.startReminderOverride),
                event: event,
                now: now,
                into: &planned)
            appendIfDue(
                .eventEnd, anchor: event.endDate, action: settings.eventEnd, event: event, now: now,
                into: &planned)
            if FullscreenNotificationEligibilityPolicy.isEligible(
                hasMeetingLink: event.hasMeetingLink,
                isAllDay: event.isAllDay,
                fullscreenNotificationsEnabled: settings.fullscreen.enabled,
                includesEventsWithoutMeetingLink:
                    settings.fullscreenNotificationsForEventsWithoutMeetingLink
            ) {
                appendIfDue(
                    .fullscreen, anchor: event.startDate, action: settings.fullscreen, event: event,
                    now: now, into: &planned)
            }
            appendIfDue(
                .autoJoin, anchor: event.startDate, action: settings.autoJoin, event: event,
                now: now, into: &planned)
            if event.hasMeetingLink {
                appendIfDue(
                    .scriptOnStart,
                    anchor: event.startDate,
                    action: settings.scriptOnStart,
                    event: event,
                    now: now,
                    into: &planned
                )
            }
        }

        return planned.sorted { $0.fireDate < $1.fireDate }
    }

    /// The start-reminder action for one event, after its override.
    ///
    /// Only the START reminder is overridable. The end reminder, fullscreen,
    /// auto-join and the on-start script stay global on purpose: they are
    /// workflow settings rather than per-meeting ones, and "why did this meeting
    /// auto-join when the others didn't" is a far worse surprise than a missing
    /// reminder.
    private static func startAction(
        global: NotificationPlanningSettings.Action,
        override: StartReminderOverride?
    ) -> NotificationPlanningSettings.Action {
        switch override {
        case nil:
            return global
        case .suppressed:
            return .disabled
        case .offset(let seconds):
            // An explicit per-event time wins even when the global reminder is
            // OFF: asking for a reminder on this meeting is a clearer signal
            // than the blanket setting, and the alternative is a control that
            // silently does nothing.
            return NotificationPlanningSettings.Action(enabled: true, offset: seconds)
        }
    }

    private static func shouldConsider(event: NotificationPlanningEvent, dismissed: Set<String>)
        -> Bool {
        if dismissed.contains(event.id) { return false }
        if event.status == .canceled { return false }
        if event.participationStatus == .declined { return false }
        if event.isAllDay { return false }
        return true
    }

    // swiftlint:disable:next function_parameter_count
    private static func appendIfDue(
        _ kind: NotificationKind,
        anchor: Date,
        action: NotificationPlanningSettings.Action,
        event: NotificationPlanningEvent,
        now: Date,
        into planned: inout [PlannedNotification]
    ) {
        guard action.enabled else { return }
        let fireDate = anchor.addingTimeInterval(-action.offset)
        guard fireDate > now else { return }
        planned.append(
            PlannedNotification(
                eventID: event.id,
                kind: kind,
                fireDate: fireDate,
                identity: identity(eventID: event.id, anchor: anchor, kind: kind, offset: action.offset)
            ))
    }

    private static func identity(
        eventID: String,
        anchor: Date,
        kind: NotificationKind,
        offset: TimeInterval
    ) -> String {
        "\(eventID)|\(Int(anchor.timeIntervalSince1970))|\(kind.rawValue)|\(Int(offset))"
    }
}
