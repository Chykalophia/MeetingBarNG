//
//  EventSearch+MeetingBar.swift
//  MeetingBarNG
//
//  App-target bridge from MBEvent to the hostless SearchableEvent projection.
//  Depends on MBEvent, so it stays OUT of the MeetingBarLogic SPM sources (it is
//  picked up automatically by the app target's synchronized folder group).
//

import Foundation

extension SearchableEvent {
    /// Projects an `MBEvent` for ranked search. Title/notes/location pass
    /// straight through; attendees fold in every attendee name+email plus the
    /// organizer (people-search should find the organizer too).
    init(event: MBEvent, sourceIndex: Int) {
        let attendeePeople = event.attendees.flatMap { [$0.name, $0.email].compactMap { $0 } }
        let organizerPeople = [event.organizer?.name, event.organizer?.email].compactMap { $0 }
        self.init(
            sourceIndex: sourceIndex,
            id: event.id,
            title: event.title,
            notes: event.notes,
            location: event.location,
            attendees: attendeePeople + organizerPeople
        )
    }
}
