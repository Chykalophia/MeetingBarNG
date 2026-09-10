//
//  MBCalendar.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 09.04.2022.
//  Copyright © 2022 Andrii Leitsius. All rights reserved.
//

import AppKit

public struct MBCalendar: Hashable, Sendable {
    let title: String
    let id: String
    /// The account/source NAME as the provider reports it — "iCloud", a Google
    /// address, an Exchange server. Free-form and display-only; it is not the
    /// thing that says which store this calendar came from. See `provider`.
    let source: String
    let email: String?
    let color: NSColor
    /// Which connected source produced this calendar. With more than one source
    /// connected at a time, calendars from both arrive in a single array, so
    /// fetching has to be able to route each one back to the store that owns it
    /// and deduplication has to know which copy of a shared meeting to prefer.
    ///
    /// Defaults to `.macOSEventKit` because that is what every call site outside
    /// the Google store means: fixtures, previews, the event writer, and the
    /// EventKit store itself.
    let provider: EventStoreProvider

    init(
        title: String,
        id: String,
        source: String?,
        email: String?,
        color: NSColor,
        provider: EventStoreProvider = .macOSEventKit
    ) {
        self.title = title
        self.id = id
        self.source = source ?? "unknown"
        self.email = email
        self.color = color
        self.provider = provider
    }
}
