//
//  GoogleEventColors.swift
//  MeetingBarNG
//
//  Google's per-event colour palette.
//
//  A Google event can override its calendar's colour with a `colorId` — the
//  eleven named colours ("Tomato", "Basil", "Peacock" …) the web UI offers on a
//  single event. EventKit has no equivalent: `EKEvent` has no colour of its own
//  and inherits its calendar's, so this is detail only the direct provider can
//  supply, and the reason the dropdown's timeline was one flat colour per
//  calendar no matter how the day actually looked in Google Calendar.
//
//  The palette is FETCHED from `/colors` rather than hardcoded. The values have
//  been stable for years and hardcoding would have worked, but the whole point
//  is matching what the user sees in Google Calendar — a copy that silently
//  drifts is worse than no colour at all. Google documents the endpoint as
//  rarely changing and asks that it be cached, which is what the store does.
//
//  Parsing lives here, hostless, so the response shape is tested without a
//  network. Resolution degrades quietly: an unknown or absent `colorId` means
//  "use the calendar's colour", which is exactly the previous behaviour.
//

import Foundation

/// `colorId` → hex, for the two palettes `/colors` returns.
///
/// Only `event` is used. Calendar colours arrive on the calendarList entries
/// as a literal `backgroundColor`, so the `calendar` palette would be a second
/// way to learn something already known.
public struct GoogleColorPalette: Equatable, Sendable {
    /// Event `colorId` → background hex, e.g. `"11"` → `"#dc2127"`.
    public let eventBackgrounds: [String: String]

    public init(eventBackgrounds: [String: String]) {
        self.eventBackgrounds = eventBackgrounds
    }

    public static let empty = GoogleColorPalette(eventBackgrounds: [:])

    public var isEmpty: Bool { eventBackgrounds.isEmpty }

    /// The background hex for an event's `colorId`, or `nil` when it has none
    /// or names a colour this palette does not know. Both mean "fall back to
    /// the calendar's colour".
    public func background(forEventColorID colorID: String?) -> String? {
        guard let colorID, !colorID.isEmpty else { return nil }
        return eventBackgrounds[colorID]
    }

    /// Parses the `/colors` response.
    ///
    /// ```
    /// { "kind": "calendar#colors",
    ///   "event": { "1": { "background": "#a4bdfc", "foreground": "#1d1d1d" } } }
    /// ```
    ///
    /// Entries without a usable background are dropped rather than defaulted:
    /// a missing colour has a correct answer already (the calendar's), so
    /// inventing one would be strictly worse.
    public static func parse(_ json: [String: Any]) -> GoogleColorPalette {
        guard let event = json["event"] as? [String: Any] else { return .empty }

        var backgrounds: [String: String] = [:]
        for (colorID, value) in event {
            guard let entry = value as? [String: Any],
                  let background = entry["background"] as? String,
                  GoogleColorPalette.isHexColor(background)
            else { continue }
            backgrounds[colorID] = background
        }
        return GoogleColorPalette(eventBackgrounds: backgrounds)
    }

    /// `#rrggbb` or `#rgb`. Guards the parser rather than the colour converter,
    /// so a malformed value is dropped at the boundary instead of reaching the
    /// UI as black.
    static func isHexColor(_ value: String) -> Bool {
        guard value.hasPrefix("#") else { return false }
        let digits = value.dropFirst()
        guard digits.count == 6 || digits.count == 3 else { return false }
        return digits.allSatisfy(\.isHexDigit)
    }
}
