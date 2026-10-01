//
//  PreviewFixtures.swift
//  MeetingBarNG
//
//  Fixture data for the Preferences dropdown preview (Phase 3). Builds a
//  `StatusBarMenuState` with deterministic sample events so the preview pane
//  can mount the REAL `DropdownPanelView` instead of a hand-copied mock —
//  eliminating the drift that the old `DisplayPreviewPane`'s duplicated
//  composition math and row layouts caused.
//
//  Lives in the app target (not MeetingBarLogic) because `MBEvent` needs
//  `MBCalendar` which holds an `NSColor`, and neither type is in the logic
//  package's sources allowlist.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import AppKit
import Defaults
import Foundation

@MainActor
enum PreviewFixtures {
    /// A fixed reference date so the preview is deterministic — identical at
    /// 3am with an empty calendar and snapshot-testable. Called fresh each time
    /// so the relative offsets ("25m from now") stay meaningful.
    static var now: Date { Date() }

    // MARK: - Sample calendars

    static let workCalendar = MBCalendar(
        title: "Work",
        id: "preview-work",
        source: "iCloud",
        email: nil,
        color: NSColor(calibratedRed: 0.23, green: 0.51, blue: 0.96, alpha: 1)
    )

    static let personalCalendar = MBCalendar(
        title: "Personal",
        id: "preview-personal",
        source: "iCloud",
        email: nil,
        color: NSColor(calibratedRed: 0.30, green: 0.74, blue: 0.40, alpha: 1)
    )

    static let focusCalendar = MBCalendar(
        title: "Focus",
        id: "preview-focus",
        source: "Google",
        email: nil,
        color: NSColor(calibratedRed: 0.95, green: 0.61, blue: 0.17, alpha: 1)
    )

    // MARK: - Sample events

    static var sampleEvents: [MBEvent] {
        let calendar = Calendar.current
        func at(_ minutes: Int) -> Date {
            calendar.date(byAdding: .minute, value: minutes, to: now) ?? now
        }

        let next = MBEvent(
            id: "preview-next",
            lastModifiedDate: nil,
            title: "preferences_preview_sample_event".loco(),
            status: .confirmed,
            notes: "https://zoom.us/j/123",
            location: nil,
            url: nil,
            organizer: nil,
            startDate: at(25),
            endDate: at(55),
            isAllDay: false,
            recurrent: false,
            calendar: workCalendar
        )

        let later = MBEvent(
            id: "preview-later",
            lastModifiedDate: nil,
            title: "preferences_display_preview_sample_event_2".loco(),
            status: .confirmed,
            notes: nil,
            location: nil,
            url: nil,
            organizer: nil,
            startDate: at(90),
            endDate: at(150),
            isAllDay: false,
            recurrent: false,
            calendar: personalCalendar
        )

        let evening = MBEvent(
            id: "preview-evening",
            lastModifiedDate: nil,
            title: "preferences_display_preview_sample_event_3".loco(),
            status: .confirmed,
            notes: nil,
            location: nil,
            url: nil,
            organizer: nil,
            startDate: at(240),
            endDate: at(300),
            isAllDay: false,
            recurrent: false,
            calendar: focusCalendar
        )

        return [next, later, evening]
    }

    /// A meeting that already ended — shown dimmed when "Hide finished" is off,
    /// removed when it's on, so toggling that setting visibly changes the preview.
    static var finishedEvent: MBEvent {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .minute, value: -60, to: now) ?? now
        let end = calendar.date(byAdding: .minute, value: -30, to: now) ?? now
        return MBEvent(
            id: "preview-finished",
            lastModifiedDate: nil,
            title: "preferences_display_preview_sample_finished".loco(),
            status: .confirmed,
            notes: nil,
            location: nil,
            url: nil,
            organizer: nil,
            startDate: start,
            endDate: end,
            isAllDay: false,
            recurrent: false,
            calendar: workCalendar
        )
    }

    // MARK: - Sample bookmarks

    static var sampleBookmarks: [Bookmark] {
        [
            Bookmark(
                name: "preferences_display_preview_sample_event_2".loco(),
                service: MeetingServices.zoom.rawValue,
                url: URL(string: "https://zoom.us/j/456")!
            ),
            Bookmark(
                name: "preferences_display_preview_sample_event_3".loco(),
                service: MeetingServices.teams.rawValue,
                url: URL(string: "https://teams.microsoft.com/l/meet")!
            )
        ]
    }

    // MARK: - Sample reminder

    static var sampleReminder: MBReminder {
        MBReminder(
            id: "preview-reminder",
            title: "preferences_display_preview_sample_reminder".loco(),
            notes: nil,
            dueDate: now.addingTimeInterval(120 * 60),
            hasTime: true,
            priority: 0,
            isCompleted: false,
            listTitle: "Reminders",
            listColor: NSColor.systemOrange,
            isOverdue: false
        )
    }

    // MARK: - Fixture state

    /// A `StatusBarMenuState` populated with sample events, bookmarks, and the
    /// user's current settings — so the real `DropdownPanelView` renders against
    /// meaningful data that re-renders when any preference changes.
    static func makeState(includeFinished: Bool, includeReminders: Bool) -> StatusBarMenuState {
        let calendar = Calendar.current
        let events = includeFinished ? [finishedEvent] + sampleEvents : sampleEvents
        let summary = DaySummary(
            timeOfDay: DaySummaryPolicy.timeOfDay(now: now, calendar: calendar),
            eventCount: sampleEvents.count,
            freeMinutes: 180
        )

        var settings = AppSettings.current
        settings.meetings.bookmarks = sampleBookmarks
        if includeReminders {
            settings.menu.showRemindersInMenu = true
        }

        return StatusBarMenuState(
            todayEvents: events,
            tomorrowEvents: [],
            nextEvent: sampleEvents.first,
            todayReminders: includeReminders ? [sampleReminder] : [],
            providerStatus: .connected(lastRefresh: nil),
            settings: settings,
            hasSelectedCalendars: true,
            hasMultipleSelectedCalendars: true,
            showTimeline: settings.menu.showTimelineInMenu,
            daySummary: summary,
            greetingName: resolvedGreetingName,
            showGreetingHeader: Defaults[.showGreetingInMenu],
            timeFormat: Defaults[.timeFormat]
        )
    }

    /// The user's greeting name (first component), or a localized sample name.
    private static var resolvedGreetingName: String {
        let name = Defaults[.greetingName].trimmingCharacters(in: .whitespacesAndNewlines)
        let source = name.isEmpty ? "preferences_display_preview_greeting_name".loco() : name
        return source.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? source
    }
}
