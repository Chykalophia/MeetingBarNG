//
//  FakeCalendar.swift
//  MeetingBarTests
//

import AppKit

@testable import Punctual

func makeFakeCalendar(
    id: String = "cal-default",
    title: String = "Test Calendar",
    source: String? = nil,
    email: String? = nil,
    color: NSColor = .black,
    provider: EventStoreProvider = .macOSEventKit
) -> MBCalendar {
    MBCalendar(
        title: title, id: id, source: source, email: email, color: color, provider: provider)
}
