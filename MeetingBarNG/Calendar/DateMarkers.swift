//
//  DateMarkers.swift
//  MeetingBarNG
//
//  User-defined markers for important days — a birthday, an anniversary, a
//  deadline — drawn on the month grids alongside the event dots.
//
//  Hostless: the model, its storage encoding, and the "does this marker fall on
//  this day" rule. No AppKit, no Defaults, no EventKit.
//
//  A marker stores month/day/year COMPONENTS rather than a `Date`. A birthday is
//  a calendar day, not an instant: stored as a `Date` at local midnight it lands
//  on the wrong day the moment the machine changes time zone, and "26 Dec" in
//  Sydney is "25 Dec" in Chicago. Components sidestep that entirely, and they
//  make an annually-repeating marker the natural case rather than a recurrence
//  rule bolted on afterwards.
//
//  Original work for MeetingBarNG by Peter Krzyzek / Chykalophia, 2026.
//

import Foundation

/// One marked day.
public struct DateMarker: Equatable, Sendable {
    /// 1–12.
    public let month: Int
    /// 1–31. Not validated against the month: 29 February is legitimate and
    /// simply matches nothing in a common year, which is the correct behaviour
    /// for a marker rather than an error to surface.
    public let day: Int
    /// `nil` means every year — the birthday case.
    public let year: Int?
    public let label: String

    public init(month: Int, day: Int, year: Int? = nil, label: String) {
        self.month = month
        self.day = day
        self.year = year
        self.label = label
    }

    public var repeatsAnnually: Bool { year == nil }
}

/// Storage encoding for `Defaults`.
///
/// A compact string per marker rather than a `Codable` blob, matching how
/// `dropdownDensity` and `menuBarTokens` are stored: the hostless module cannot
/// import Defaults, and a plist a human can read is worth more than a nested
/// archive when something goes wrong.
///
/// Format: `YYYY-MM-DD|label`, with `----` for a repeating year, mirroring how
/// iCalendar writes a floating date. The label may contain anything except a
/// newline; a `|` inside it is safe because only the FIRST separator is split on.
public enum DateMarkerCodec {
    private static let separator: Character = "|"
    private static let repeatingYear = "----"

    public static func encode(_ marker: DateMarker) -> String {
        let year = marker.year.map { String(format: "%04d", $0) } ?? repeatingYear
        let date = String(format: "%@-%02d-%02d", year, marker.month, marker.day)
        return "\(date)\(separator)\(marker.label)"
    }

    public static func decode(_ raw: String) -> DateMarker? {
        // Split once: a label containing "|" must survive a round trip.
        guard let separatorIndex = raw.firstIndex(of: separator) else { return nil }
        let datePart = String(raw[raw.startIndex ..< separatorIndex])
        let label = String(raw[raw.index(after: separatorIndex)...])
        guard !label.isEmpty else { return nil }

        let fields = datePart.split(separator: "-", omittingEmptySubsequences: false)
        // "-----12-25" splits into ["", "", "", "", "12", "25"]; a real year gives
        // ["2026", "12", "25"]. Normalise by taking the last two as month/day.
        guard fields.count >= 3 else { return nil }
        guard let day = Int(fields[fields.count - 1]),
              let month = Int(fields[fields.count - 2]) else { return nil }
        guard (1 ... 12).contains(month), (1 ... 31).contains(day) else { return nil }

        let yearField = fields[0 ..< (fields.count - 2)].joined(separator: "-")
        let year = yearField == repeatingYear ? nil : Int(yearField)
        // A year field that is neither the repeating sentinel nor a number is
        // corrupt — reject rather than silently promoting it to "every year".
        if year == nil, yearField != repeatingYear { return nil }

        return DateMarker(month: month, day: day, year: year, label: label)
    }

    /// Decodes a stored list, dropping entries that do not parse.
    ///
    /// Silently, and deliberately: a hand-edited plist or a value from a future
    /// build should cost the user that one marker, not the whole list.
    public static func decodeAll(_ raws: [String]) -> [DateMarker] {
        raws.compactMap(decode)
    }

    public static func encodeAll(_ markers: [DateMarker]) -> [String] {
        markers.map(encode)
    }
}

public enum DateMarkerPolicy {
    /// The markers falling on `date`, in the order they were stored.
    ///
    /// Dated markers are matched on all three components; repeating ones ignore
    /// the year. Comparison is on the calendar's own components, so a marker is
    /// on the day the user's calendar says it is, whatever the time of day the
    /// caller passes in.
    public static func markers(
        on date: Date,
        from markers: [DateMarker],
        calendar: Calendar
    ) -> [DateMarker] {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else { return [] }

        return markers.filter { marker in
            guard marker.month == month, marker.day == day else { return false }
            guard let markerYear = marker.year else { return true }
            return markerYear == year
        }
    }

    /// Whether `date` carries any marker. The grid asks this per cell, so it
    /// avoids building an array it would immediately discard.
    public static func hasMarker(
        on date: Date,
        from markers: [DateMarker],
        calendar: Calendar
    ) -> Bool {
        // Qualified: the `markers` parameter shadows the function of the same name.
        !DateMarkerPolicy.markers(on: date, from: markers, calendar: calendar).isEmpty
    }
}
