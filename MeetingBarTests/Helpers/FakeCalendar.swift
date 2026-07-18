//
//  FakeCalendar.swift
//  MeetingBarTests
//

import AppKit

@testable import MeetingBarNG

func makeFakeCalendar(
    id: String = "cal-default",
    title: String = "Test Calendar",
    source: String? = nil,
    email: String? = nil,
    color: NSColor = .black
) -> MBCalendar {
    MBCalendar(title: title, id: id, source: source, email: email, color: color)
}
