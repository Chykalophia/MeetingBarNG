//
//  MeetingSummaryPresenter.swift
//  MeetingBarNG
//
//  Turns an event into the copy the meeting card shows — section title, title,
//  metadata line, countdown.
//
//  Extracted from `MenuBuilder` so the SwiftUI panel stops reaching into an
//  NSMenu builder for it. The panel used to construct a whole `MenuBuilder`
//  (passing `NSNull()` as the target, since it has no @objc actions) purely to
//  call this one method, which is what kept a 1,800-line menu renderer alive
//  after the menu itself became a fallback.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Foundation

/// What the meeting card is allowed to show.
///
/// Individual switches rather than named presets. The useful combinations are
/// not the ones a preset list would guess — "everything except the times" and
/// "just the title and the bar" are both reasonable, and so is anything between.
///
/// The title is not a member: a card with no title is not a card.
struct MeetingCardFields: Equatable, Sendable {
    /// The "Next meeting • in 2h" line above the title.
    var showsSectionLine = true
    /// The start–end range in the metadata line.
    var showsTimes = true
    /// The meeting service ("Google Meet", "Zoom").
    var showsProvider = true
    /// Which calendar and account the meeting came from.
    var showsSource = true

    static let all = MeetingCardFields()
}

enum MeetingSummaryPresenter {
    /// The meeting card's copy for `event`.
    ///
    /// Takes the three things it actually needs rather than a whole
    /// `StatusBarMenuState`: the event, how to format a time, and what "now" is.
    /// `now` is injected so the countdown is testable and so the panel can pass
    /// its own ticking clock instead of `Date()`.
    static func presentation(
        for event: MBEvent,
        timeFormat: TimeFormat,
        now: Date,
        fields: MeetingCardFields = .all
    ) -> MeetingSummaryPresentation {
        let isCurrent = event.startDate <= now && event.endDate > now
        let eventTitle = event.title.isEmpty
            ? "status_bar_no_title".loco()
            : event.title
        let time = timeStrings(for: event, timeFormat: timeFormat)
        let timeRange = event.isAllDay ? time.start : "\(time.start) – \(time.end)"
        let meetingProvider = fields.showsProvider
            ? event.meetingLink?.service.flatMap(MeetingProvider.provider(for:))?.displayName
            : nil
        let account = fields.showsSource
            ? firstMeaningfulValue([
                event.calendar.email,
                event.calendar.source == "unknown" ? nil : event.calendar.source,
                event.organizer?.email
            ])
            : nil

        let countdown: String?
        if !fields.showsSectionLine || isCurrent || event.isAllDay {
            countdown = nil
        } else {
            let timeLeft = StatusBarTitlePolicy.formattedTimeLeft(
                from: now,
                to: event.startDate,
                calendar: Calendar.current
            )
            countdown = timeLeft.isEmpty ? nil : "status_bar_event_status_in".loco(timeLeft)
        }

        return MeetingSummaryPresentation(
            // Empty rather than optional: the view already drops an empty
            // section line, and an extra optional would mean two ways to say
            // "nothing here".
            sectionTitle: fields.showsSectionLine
                ? (isCurrent
                    ? "status_bar_control_current_meeting".loco()
                    : "status_bar_control_next_meeting".loco())
                : "",
            eventTitle: eventTitle,
            metadata: uniqueValues([
                fields.showsTimes ? timeRange : nil,
                meetingProvider,
                account,
                fields.showsSource ? event.calendar.title : nil
            ]),
            meetingService: event.meetingLink?.service,
            countdown: countdown
        )
    }

    /// Start and end as the user's chosen format writes them. An all-day event
    /// has no clock time, so it says so and leaves the end blank rather than
    /// printing a meaningless midnight-to-midnight range.
    static func timeStrings(
        for event: MBEvent,
        timeFormat: TimeFormat
    ) -> (start: String, end: String) {
        guard !event.isAllDay else {
            return ("status_bar_event_start_time_all_day".loco(), "")
        }

        let formatter = DateFormatter()
        formatter.locale = I18N.instance.locale
        switch timeFormat {
        case .am_pm: formatter.dateFormat = "h:mm a"
        case .military: formatter.dateFormat = "HH:mm"
        }
        return (
            formatter.string(from: event.startDate),
            formatter.string(from: event.endDate)
        )
    }

    /// The first value that is actually something, after trimming.
    static func firstMeaningfulValue(_ values: [String?]) -> String? {
        values.lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// Non-empty values in order, without repeats.
    ///
    /// Compared case- and diacritic-insensitively, because the same account
    /// reaches this list from several sources with different capitalisation and
    /// the metadata line should not say it twice.
    static func uniqueValues(_ values: [String?]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty
            else { return nil }
            let identity = trimmed.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard seen.insert(identity).inserted else { return nil }
            return trimmed
        }
    }
}
