//
//  EventSelection+MeetingBar.swift
//  MeetingBar
//

import Defaults
import Foundation

extension EventSelectionSettings {
    static var current: EventSelectionSettings {
        EventSelectionSettings(
            period: EventSelectionPeriod(Defaults[.showEventsForPeriod]),
            includesPersonalEvents: Defaults[.personalEventsAppereance] == .show_active,
            dismissedEvents: Set(Defaults[.dismissedEvents].map {
                EventSelectionDismissal(id: $0.id, lastModifiedDate: $0.lastModifiedDate)
            }),
            requiresMeetingLinkForNonAllDayEvents: Defaults[.nonAllDayEvents].requiresMeetingLink,
            hidesPendingEvents: Defaults[.showPendingEvents].hidesFromNextEvent,
            hidesTentativeEvents: Defaults[.showTentativeEvents].hidesFromNextEvent,
            ongoingEventVisibility: EventSelectionOngoingVisibility(Defaults[.ongoingEventVisibility])
        )
    }
}

extension EventSelectionEvent {
    init(event: MBEvent, sourceIndex: Int) {
        self.init(
            sourceIndex: sourceIndex,
            id: event.id,
            lastModifiedDate: event.lastModifiedDate,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            hasMeetingLink: event.meetingLink != nil,
            hasAttendees: !event.attendees.isEmpty,
            status: event.status == .canceled ? .canceled : .active,
            participationStatus: EventSelectionEvent.ParticipationStatus(event.participationStatus)
        )
    }
}

private extension EventSelectionPeriod {
    init(_ period: ShowEventsForPeriod) {
        switch period {
        case .today:
            self = .today
        case .today_n_tomorrow,
             .today_n_tomorrow_next,
             .today_n_tomorrow_summary:
            self = .todayAndTomorrow
        }
    }
}

private extension EventSelectionOngoingVisibility {
    init(_ visibility: OngoingEventVisibility) {
        switch visibility {
        case .hideImmediateAfter:
            self = .hideImmediateAfter
        case .showTenMinAfter:
            self = .showTenMinAfter
        case .showTenMinBeforeNext:
            self = .showTenMinBeforeNext
        }
    }
}

private extension EventSelectionEvent.ParticipationStatus {
    init(_ status: MBEventAttendeeStatus) {
        switch status {
        case .declined:
            self = .declined
        case .pending:
            self = .pending
        case .tentative:
            self = .tentative
        case .unknown, .accepted, .delegated, .completed, .inProcess:
            self = .active
        }
    }
}

private extension NonAlldayEventsAppereance {
    var requiresMeetingLink: Bool {
        self == .show_inactive_without_meeting_link || self == .hide_without_meeting_link
    }
}

extension OngoingEventVisibility {
    /// How long after a meeting starts it stops being the "current" meeting,
    /// or nil when the answer does not depend on elapsed time.
    ///
    /// Kept next to the selection logic it mirrors: `StatusBarTickPolicy` uses
    /// it to schedule a redraw at exactly that instant, and a value that
    /// disagreed with `EventSelection.nextEvent` would redraw at the wrong
    /// moment. `.hideImmediateAfter` returns 0 (the transition is the start
    /// itself) and `.showTenMinBeforeNext` returns nil, since its handover is
    /// driven by the *next* meeting's start, which is already a transition.
    var gracePeriod: TimeInterval? {
        switch self {
        case .hideImmediateAfter: return 0
        case .showTenMinAfter: return 600
        case .showTenMinBeforeNext: return nil
        }
    }
}

private extension PendingEventsAppereance {
    var hidesFromNextEvent: Bool {
        self == .hide || self == .show_inactive
    }
}

private extension TentativeEventsAppereance {
    var hidesFromNextEvent: Bool {
        self == .hide || self == .show_inactive
    }
}
